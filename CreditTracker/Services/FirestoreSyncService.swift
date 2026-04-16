import Foundation
import SwiftData
import FirebaseCore
import FirebaseFirestore

// MARK: - FirestoreSyncService

/// A lightweight Firestore sync bus that mirrors PeriodLog state across devices.
///
/// ## Architecture
/// SwiftData is the authoritative source of truth. Firestore is a dumb mirror that
/// stores only the fields declared in `FirestoreSyncable.firestorePayload()`.
///
/// ## Data Flow
/// ```
/// User action → SwiftData save → upload(_:) → Firestore
/// Remote change → Firestore snapshot → applySnapshot → SwiftData save → UI refresh
/// ```
///
/// ## Conflict Resolution
/// Last-write-wins via Firestore server timestamps. The server timestamp of the most
/// recent write to a document is authoritative. Suitable for single-user multi-device use.
///
/// ## Firestore Document Path
/// ```
/// /users/{userID}/periodLogs/{periodLog.id}
/// ```
///
/// ## Multi-Device Sync
/// Requires a shared `userID` across devices. By default a stable device-scoped UUID
/// is used, which provides single-device cloud backup. Call `setUserID(_:)` with a
/// Firebase Auth UID after sign-in to enable true cross-device sync.
@MainActor
@Observable
final class FirestoreSyncService {

    static let shared = FirestoreSyncService()

    // MARK: - Observable State

    private(set) var syncState: SyncState = .idle
    private(set) var lastSyncedAt: Date? = nil

    // MARK: - Private State

    private var db: Firestore { Firestore.firestore() }
    private var modelContext: ModelContext?
    private var activeListeners: [ListenerRegistration] = []

    /// Document IDs for PeriodLogs we have written locally but whose server
    /// confirmation has not yet arrived via the snapshot listener.
    ///
    /// Purpose: prevents applying our own writes back to SwiftData as remote changes.
    /// Each ID is inserted after a successful local write and removed when the
    /// Firestore listener delivers the server-confirmed version (hasPendingWrites == false).
    private var pendingUploadIDs: Set<String> = []

    /// Firestore path namespace for this user.
    /// Persisted across launches so PeriodLog documents accumulate under the same path.
    private(set) var userID: String = {
        if let stored = UserDefaults.standard.string(forKey: Constants.firestoreUserIDKey) {
            return stored
        }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: Constants.firestoreUserIDKey)
        return id
    }()

    private init() {}

    // MARK: - Setup

    /// Configures the service with the app's live model context.
    /// Must be called before `startListening()` or `upload(_:)`.
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Overrides the user ID — e.g. after Firebase Auth sign-in for cross-device sync.
    /// Tears down existing listeners and restarts them under the new Firestore path.
    func setUserID(_ id: String) {
        guard id != userID else { return }
        stopListening()
        userID = id
        UserDefaults.standard.set(id, forKey: Constants.firestoreUserIDKey)
        startListening()
    }

    // MARK: - Family Sync Management

    /// Joins an existing Family Sync group using a shared ID.
    ///
    /// This method performs the necessary steps to safely transition the device
    /// to a new shared data source:
    /// 1. Stops all active network listeners.
    /// 2. Wipes the local SwiftData cache to prevent mixing user data.
    /// 3. Updates the local identity to the shared Family ID.
    /// 4. Restarts the sync engine to pull the remote data.
    func joinFamilySync(id: String, context: ModelContext) throws {
        guard id != userID else { return }
        
        stopListening()
        
        do {
            try wipeLocalData(context: context)
        } catch {
            throw SyncError.localWipeFailed(underlying: error)
        }
        
        userID = id
        UserDefaults.standard.set(id, forKey: Constants.firestoreUserIDKey)
        UserDefaults.standard.set(true, forKey: "isFamilySyncEnabled") // Marker you can use in UI
        
        startListening()
    }

    /// Completely wipes the local SwiftData cache.
    /// Deletes root models only — cascade delete rules handle their children.
    /// IMPORTANT: Any new root @Model type added to the schema must be listed here.
    private func wipeLocalData(context: ModelContext) throws {
        // Card → Credit (cascade) → PeriodLog (cascade): deleting all Cards is sufficient.
        let cards = try context.fetch(FetchDescriptor<Card>())
        cards.forEach { context.delete($0) }

        // BonusCard has no parent relationship so cascade cannot reach it.
        // Must be deleted explicitly to prevent orphaned data after a family join.
        let bonusCards = try context.fetch(FetchDescriptor<BonusCard>())
        bonusCards.forEach { context.delete($0) }

        // FamilySettings is a family-wide singleton — wipe it so the new family's
        // Firestore document is pulled in fresh when listeners re-attach.
        let familySettingsItems = try context.fetch(FetchDescriptor<FamilySettings>())
        familySettingsItems.forEach { context.delete($0) }

        // LoyaltyProgram has no parent relationship so cascade cannot reach it.
        // Must be deleted explicitly to prevent orphaned data after a family join.
        let loyaltyPrograms = try context.fetch(FetchDescriptor<LoyaltyProgram>())
        loyaltyPrograms.forEach { context.delete($0) }

        // CardApplication has no parent relationship — must be wiped explicitly.
        let cardApplications = try context.fetch(FetchDescriptor<CardApplication>())
        cardApplications.forEach { context.delete($0) }

        try context.save()
    }

    // MARK: - Listener Lifecycle

    /// Attaches real-time Firestore listeners for Card, Credit, and PeriodLog documents.
    ///
    /// - Safe to call multiple times: a second call while already listening is a no-op.
    /// - Call on `scenePhase == .active`.
    func startListening() {
        guard modelContext != nil, activeListeners.isEmpty, FirebaseApp.app() != nil else { return }

        let cardReg = collection(for: Card.self).addSnapshotListener { [weak self] snapshot, _ in
            self?.handleSnapshot(snapshot, type: .card)
        }
        
        let creditReg = collection(for: Credit.self).addSnapshotListener { [weak self] snapshot, _ in
            self?.handleSnapshot(snapshot, type: .credit)
        }
        
        let logReg = collection(for: PeriodLog.self).addSnapshotListener { [weak self] snapshot, _ in
            self?.handleSnapshot(snapshot, type: .periodLog)
        }

        // FamilySettings is a singleton collection — one document per family.
        let settingsReg = collection(for: FamilySettings.self).addSnapshotListener { [weak self] snapshot, _ in
            self?.handleSnapshot(snapshot, type: .familySettings)
        }

        // BonusCard documents live in their own sub-collection and are synced
        // independently of the card/credit/periodLog hierarchy.
        let bonusReg = collection(for: BonusCard.self).addSnapshotListener { [weak self] snapshot, _ in
            self?.handleSnapshot(snapshot, type: .bonusCard)
        }

        // LoyaltyProgram documents live in their own sub-collection and are synced
        // independently of the card/credit hierarchy.
        let loyaltyReg = collection(for: LoyaltyProgram.self).addSnapshotListener { [weak self] snapshot, _ in
            self?.handleSnapshot(snapshot, type: .loyaltyProgram)
        }

        // CardApplication documents power the Card Planner feature.
        let appReg = collection(for: CardApplication.self).addSnapshotListener { [weak self] snapshot, _ in
            self?.handleSnapshot(snapshot, type: .cardApplication)
        }

        activeListeners.append(contentsOf: [cardReg, creditReg, logReg, settingsReg, bonusReg, loyaltyReg, appReg])
    }

    /// Removes all Firestore listeners to avoid background network traffic.
    /// Call on `scenePhase == .background`.
    func stopListening() {
        activeListeners.forEach { $0.remove() }
        activeListeners.removeAll()
    }

    // MARK: - Upload (SwiftData → Firestore)

    /// Uploads the syncable fields of any FirestoreSyncable model to Firestore.
    ///
    /// Always call *after* `context.save()` so local state is committed first.
    /// Uses `merge: true` so only declared sync fields are touched — any extra
    /// Firestore fields (e.g. future server-side analytics) are preserved.
    ///
    /// Firestore's offline persistence means the write is queued locally if the
    /// device is offline and flushed automatically when connectivity returns.
    func upload<T: FirestoreSyncable>(_ item: T) async {
        guard FirebaseApp.app() != nil else { return }
        let docID = item.syncID
        syncState = .syncing

        // Insert BEFORE the await. The main actor is free to run other enqueued
        // tasks (including snapshot listener callbacks) while this function is
        // suspended at the network call below. If we inserted after, a fast
        // listener delivery during that window would not find the ID and would
        // incorrectly re-apply our own write back to SwiftData.
        pendingUploadIDs.insert(docID)

        var payload = item.firestorePayload()
        payload["updatedAt"] = FieldValue.serverTimestamp()

        do {
            try await collection(for: T.self)
                .document(docID)
                .setData(payload, merge: true)

            lastSyncedAt = Date()
            // syncState resets to .idle via handleSnapshot once pendingUploadIDs drains.
        } catch {
            // Write failed — remove the pre-inserted marker so the listener can
            // re-apply Firestore's authoritative state if needed.
            pendingUploadIDs.remove(docID)
            syncState = .error(
                SyncError.uploadFailed(id: docID, underlying: error).localizedDescription
                ?? "Upload failed"
            )
        }
    }

    // MARK: - Delete (SwiftData → Firestore)

    /// Deletes a syncable document from Firestore.
    /// Pass the item's UUID string.
    func deleteDocument<T: FirestoreSyncable>(for type: T.Type, id: String) async {
        guard FirebaseApp.app() != nil else { return }
        do {
            try await collection(for: T.self).document(id).delete()
        } catch {
            print("Failed to delete \(T.self) document \(id): \(error.localizedDescription)")
        }
    }

    /// Safely deletes a Credit and all of its PeriodLogs from Firestore.
    ///
    /// Call this *before* `context.delete(credit)` so the relationship is still intact.
    /// Without this, the snapshot listener sees the credit document still exists in
    /// Firestore on the next active-scene resume and re-creates it in SwiftData.
    func deleteCreditCascading(_ credit: Credit) async {
        let creditID = credit.syncID
        let logIDs   = credit.periodLogs.map { $0.syncID }

        // Delete children first to maintain Firestore referential integrity.
        for id in logIDs { await deleteDocument(for: PeriodLog.self, id: id) }
        await deleteDocument(for: Credit.self, id: creditID)
    }

    /// Safely deletes a Card and explicitly deletes all of its nested Credits and
    /// PeriodLogs from Firestore.
    ///
    /// Call this *before* `context.delete(card)` so the relationships are still intact.
    func deleteCardCascading(_ card: Card) async {
        // 1. Capture all IDs before any SwiftData deletion happens
        let cardID = card.syncID
        let creditIDs = card.credits.map { $0.syncID }
        let logIDs = card.credits.flatMap { $0.periodLogs }.map { $0.syncID }
        
        // 2. Delete from Firestore in reverse dependency order
        for id in logIDs { await deleteDocument(for: PeriodLog.self, id: id) }
        for id in creditIDs { await deleteDocument(for: Credit.self, id: id) }
        await deleteDocument(for: Card.self, id: cardID)
    }

    // MARK: - Snapshot Handler (Firestore → SwiftData)

    private enum SyncModelType { case card, credit, periodLog, familySettings, bonusCard, loyaltyProgram, cardApplication }

    private func handleSnapshot(_ snapshot: QuerySnapshot?, type: SyncModelType) {
        guard let snapshot else { return }
        Task { @MainActor in
            guard let context = self.modelContext else { return }
            var didApplyChanges = false

            for change in snapshot.documentChanges {
                let docID = change.document.documentID
                
                // 1. Handle Remote Deletions
                if change.type == .removed {
                    if change.document.metadata.hasPendingWrites { continue }
                    switch type {
                    case .card:
                        if let item = self.fetchCard(id: docID, in: context) { context.delete(item); didApplyChanges = true }
                    case .credit:
                        if let item = self.fetchCredit(id: docID, in: context) { context.delete(item); didApplyChanges = true }
                    case .periodLog:
                        if let item = self.fetchPeriodLog(id: docID, in: context) { context.delete(item); didApplyChanges = true }
                    case .familySettings:
                        // Don't delete FamilySettings locally when the Firestore document is
                        // removed — the singleton should persist on-device even during transient
                        // cloud inconsistencies or family-ID migrations.
                        break
                    case .bonusCard:
                        if let item = self.fetchBonusCard(id: docID, in: context) { context.delete(item); didApplyChanges = true }
                    case .loyaltyProgram:
                        if let item = self.fetchLoyaltyProgram(id: docID, in: context) { context.delete(item); didApplyChanges = true }
                    case .cardApplication:
                        if let item = self.fetchCardApplication(id: docID, in: context) { context.delete(item); didApplyChanges = true }
                    }
                    continue
                }

                // 2. Handle Remote Additions / Modifications
                guard change.type == .added || change.type == .modified else { continue }

                // Skip local writes not yet confirmed by the server.
                if change.document.metadata.hasPendingWrites { continue }

                // Consume the server confirmation of our own upload.
                if self.pendingUploadIDs.remove(docID) != nil { continue }

                let changed: Bool
                switch type {
                case .card:
                    changed = self.applyCardChange(docID: docID, data: change.document.data(), context: context)
                case .credit:
                    changed = self.applyCreditChange(docID: docID, data: change.document.data(), context: context)
                case .periodLog:
                    changed = self.applyPeriodLogChange(docID: docID, data: change.document.data(), context: context)
                case .familySettings:
                    changed = self.applyFamilySettingsChange(docID: docID, data: change.document.data(), context: context)
                case .bonusCard:
                    changed = self.applyBonusCardChange(docID: docID, data: change.document.data(), context: context)
                case .loyaltyProgram:
                    changed = self.applyLoyaltyProgramChange(docID: docID, data: change.document.data(), context: context)
                case .cardApplication:
                    changed = self.applyCardApplicationChange(docID: docID, data: change.document.data(), context: context)
                }

                if changed { didApplyChanges = true }
            }

            if self.pendingUploadIDs.isEmpty, case .syncing = self.syncState {
                self.syncState = .idle
            }
            
            if didApplyChanges { try? context.save() }
        }
    }

    // MARK: - Relational Merge Logic

    @discardableResult
    private func applyCardChange(docID: String, data: [String: Any], context: ModelContext) -> Bool {
        guard let uuid = UUID(uuidString: docID) else { return false }
        let card: Card
        var isNew = false

        if let existing = fetchCard(id: docID, in: context) {
            card = existing
        } else {
            // Create stub if missing. Real values will populate immediately below.
            card = Card(name: "Syncing...", annualFee: 0, gradientStartHex: "#000000", gradientEndHex: "#000000", sortOrder: 0)
            card.id = uuid
            context.insert(card)
            isNew = true
        }

        var changed = isNew
        if let name = data["name"] as? String, name != card.name { card.name = name; changed = true }
        if let fee = data["annualFee"] as? Double, fee != card.annualFee { card.annualFee = fee; changed = true }
        if let gStart = data["gradientStartHex"] as? String, gStart != card.gradientStartHex { card.gradientStartHex = gStart; changed = true }
        if let gEnd = data["gradientEndHex"] as? String, gEnd != card.gradientEndHex { card.gradientEndHex = gEnd; changed = true }
        if let order = data["sortOrder"] as? Int, order != card.sortOrder { card.sortOrder = order; changed = true }

        // Payment fields — guarded individually so older Firestore docs without
        // these keys don't overwrite freshly-set local values with defaults.
        if let reminderEnabled = data["paymentReminderEnabled"] as? Bool,
           reminderEnabled != card.paymentReminderEnabled {
            card.paymentReminderEnabled = reminderEnabled
            changed = true
        }
        if let reminderDays = data["paymentReminderDaysBefore"] as? Int,
           reminderDays != card.paymentReminderDaysBefore {
            card.paymentReminderDaysBefore = reminderDays
            changed = true
        }
        // paymentDueDay is optional — its absence in Firestore means the remote
        // device hasn't set a due date; treat that as nil rather than 0.
        if data.keys.contains("paymentDueDay") {
            let remoteDay = data["paymentDueDay"] as? Int  // nil when field is NSNull
            if remoteDay != card.paymentDueDay { card.paymentDueDay = remoteDay; changed = true }
        }

        // ── Annual fee reminder ────────────────────────────────────────────────
        if let reminderEnabled = data["annualFeeReminderEnabled"] as? Bool,
           reminderEnabled != card.annualFeeReminderEnabled {
            card.annualFeeReminderEnabled = reminderEnabled
            changed = true
        }
        // annualFeeDate is optional — presence in Firestore means it was set;
        // absence means the user cleared it on another device.
        if data.keys.contains("annualFeeDate") {
            if let ts = data["annualFeeDate"] as? Timestamp {
                let date = ts.dateValue()
                if date != card.annualFeeDate { card.annualFeeDate = date; changed = true }
            } else {
                // Field present but NSNull — remote device cleared the date.
                if card.annualFeeDate != nil { card.annualFeeDate = nil; changed = true }
            }
        }

        return changed
    }

    @discardableResult
    private func applyCreditChange(docID: String, data: [String: Any], context: ModelContext) -> Bool {
        guard let uuid = UUID(uuidString: docID) else { return false }
        let credit: Credit
        var isNew = false

        if let existing = fetchCredit(id: docID, in: context) {
            credit = existing
        } else {
            // Create stub if missing. Note: passing .monthly assuming init takes TimeframeType.
            credit = Credit(name: "Syncing...", totalValue: 0, timeframe: .monthly, reminderDaysBefore: 5)
            credit.id = uuid
            context.insert(credit)
            isNew = true
        }

        var changed = isNew
        if let name = data["name"] as? String, name != credit.name { credit.name = name; changed = true }
        if let value = data["totalValue"] as? Double, value != credit.totalValue { credit.totalValue = value; changed = true }
        if let timeframeStr = data["timeframe"] as? String, timeframeStr != credit.timeframe { credit.timeframe = timeframeStr; changed = true }
        if let reminderDays = data["reminderDaysBefore"] as? Int, reminderDays != credit.reminderDaysBefore { credit.reminderDaysBefore = reminderDays; changed = true }
        if let customReminder = data["customReminderEnabled"] as? Bool, customReminder != credit.customReminderEnabled { credit.customReminderEnabled = customReminder; changed = true }

        // Relational Linking to Parent Card
        if let cardID = data["cardID"] as? String, credit.card?.id.uuidString != cardID {
            guard let parentID = UUID(uuidString: cardID) else { return changed }
            var parentCard = fetchCard(id: cardID, in: context)
            
            if parentCard == nil {
                // Stub out-of-order parent. Will be populated when Card snapshot fires.
                let stub = Card(name: "Syncing...", annualFee: 0, gradientStartHex: "#000000", gradientEndHex: "#000000", sortOrder: 0)
                stub.id = parentID
                context.insert(stub)
                parentCard = stub
            }
            
            if let parent = parentCard {
                credit.card = parent
                if !parent.credits.contains(where: { $0.id == credit.id }) {
                    parent.credits.append(credit)
                }
                changed = true
            }
        }

        return changed
    }

    @discardableResult
    private func applyPeriodLogChange(docID: String, data: [String: Any], context: ModelContext) -> Bool {
        guard let uuid = UUID(uuidString: docID) else { return false }
        let periodLog: PeriodLog
        var isNew = false

        if let existing = fetchPeriodLog(id: docID, in: context) {
            periodLog = existing
        } else {
            // Create stub if missing. Note: passing .pending assuming init takes PeriodStatus.
            periodLog = PeriodLog(periodLabel: "Syncing...", periodStart: Date(), periodEnd: Date(), status: .pending)
            periodLog.id = uuid
            context.insert(periodLog)
            isNew = true
        }

        var changed = isNew
        if let label = data["periodLabel"] as? String, label != periodLog.periodLabel { periodLog.periodLabel = label; changed = true }
        
        if let startTS = data["periodStart"] as? Timestamp {
            let start = startTS.dateValue()
            if start != periodLog.periodStart { periodLog.periodStart = start; changed = true }
        }
        
        if let endTS = data["periodEnd"] as? Timestamp {
            let end = endTS.dateValue()
            if end != periodLog.periodEnd { periodLog.periodEnd = end; changed = true }
        }
        
        if let remoteStatus = data["status"] as? String, remoteStatus != periodLog.status {
            periodLog.status = remoteStatus
            changed = true
        }

        let remoteAmount = (data["claimedAmount"] as? Double) ?? (data["claimedAmount"] as? NSNumber)?.doubleValue
        if let amt = remoteAmount, amt != periodLog.claimedAmount {
            periodLog.claimedAmount = amt
            changed = true
        }

        // Relational Linking to Parent Credit
        if let creditID = data["creditID"] as? String, periodLog.credit?.id.uuidString != creditID {
            guard let parentID = UUID(uuidString: creditID) else { return changed }
            var parentCredit = fetchCredit(id: creditID, in: context)
            
            if parentCredit == nil {
                // Stub out-of-order parent. Will be populated when Credit snapshot fires.
                let stub = Credit(name: "Syncing...", totalValue: 0, timeframe: .monthly, reminderDaysBefore: 5)
                stub.id = parentID
                context.insert(stub)
                parentCredit = stub
            }
            
            if let parent = parentCredit {
                periodLog.credit = parent
                if !parent.periodLogs.contains(where: { $0.id == periodLog.id }) {
                    parent.periodLogs.append(periodLog)
                }
                changed = true
            }
        }

        return changed
    }

    // MARK: - FamilySettings Merge Logic

    /// Merges a remote `FamilySettings` document into the local SwiftData singleton.
    ///
    /// - Only the canonical document (`Constants.familySettingsSyncID`) is processed.
    /// - Creates the local singleton if it doesn't exist yet.
    /// - When the change was authored by another device (different FCM token), reschedules
    ///   the Discord Reminder notification and mirrors values to UserDefaults so that
    ///   legacy `rescheduleAll()` call sites pick up the correct time automatically.
    @discardableResult
    private func applyFamilySettingsChange(docID: String, data: [String: Any], context: ModelContext) -> Bool {
        // Guard: only process the well-known singleton document.
        guard docID == Constants.familySettingsSyncID else { return false }

        // Fetch or lazily create the local singleton.
        var descriptor = FetchDescriptor<FamilySettings>()
        descriptor.fetchLimit = 1

        let settings: FamilySettings
        var isNew = false

        if let existing = try? context.fetch(descriptor).first {
            settings = existing
        } else {
            settings = FamilySettings()
            context.insert(settings)
            isNew = true
        }

        // Apply field-level diffs (skip unchanged values to minimise dirty tracking).
        var changed = isNew
        if let enabled = data["discordReminderEnabled"] as? Bool,
           enabled != settings.discordReminderEnabled {
            settings.discordReminderEnabled = enabled; changed = true
        }
        if let hour = data["discordReminderHour"] as? Int,
           hour != settings.discordReminderHour {
            settings.discordReminderHour = hour; changed = true
        }
        if let minute = data["discordReminderMinute"] as? Int,
           minute != settings.discordReminderMinute {
            settings.discordReminderMinute = minute; changed = true
        }
        if let token = data["lastModifiedByToken"] as? String,
           token != settings.lastModifiedByToken {
            settings.lastModifiedByToken = token; changed = true
        }

        // If the document was modified by another device, update local notification
        // scheduling and mirror to UserDefaults for backward compatibility.
        if changed && !isNew {
            let myToken = UserDefaults.standard.string(forKey: Constants.fcmTokenKey) ?? ""
            if settings.lastModifiedByToken != myToken {
                let hour    = settings.discordReminderHour
                let minute  = settings.discordReminderMinute
                let enabled = settings.discordReminderEnabled

                // Mirror to UserDefaults so the zero-param scheduleDiscordReminder()
                // (called by rescheduleAll) reads the correct hour/minute.
                UserDefaults.standard.set(enabled, forKey: Constants.discordReminderEnabledKey)
                UserDefaults.standard.set(hour,    forKey: Constants.discordReminderHourKey)
                UserDefaults.standard.set(minute,  forKey: Constants.discordReminderMinuteKey)

                // Reschedule using the explicit-param overload to avoid any race
                // with UserDefaults propagation timing.
                if enabled {
                    NotificationManager.shared.scheduleDiscordReminder(hour: hour, minute: minute)
                } else {
                    NotificationManager.shared.cancelDiscordReminder()
                }
            }
        }

        return changed
    }

    // MARK: - Firestore Helpers

    private func collection<T: FirestoreSyncable>(for type: T.Type) -> CollectionReference {
        db.collection("users")
            .document(userID)
            .collection(T.firestoreCollectionName)
    }

    private func fetchCard(id: String, in context: ModelContext) -> Card? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        var descriptor = FetchDescriptor<Card>(predicate: #Predicate { $0.id == uuid })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func fetchCredit(id: String, in context: ModelContext) -> Credit? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        var descriptor = FetchDescriptor<Credit>(predicate: #Predicate { $0.id == uuid })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func fetchPeriodLog(id: String, in context: ModelContext) -> PeriodLog? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        var descriptor = FetchDescriptor<PeriodLog>(predicate: #Predicate { $0.id == uuid })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func fetchBonusCard(id: String, in context: ModelContext) -> BonusCard? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        var descriptor = FetchDescriptor<BonusCard>(predicate: #Predicate { $0.id == uuid })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func fetchLoyaltyProgram(id: String, in context: ModelContext) -> LoyaltyProgram? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        var descriptor = FetchDescriptor<LoyaltyProgram>(predicate: #Predicate { $0.id == uuid })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func fetchCardApplication(id: String, in context: ModelContext) -> CardApplication? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        var descriptor = FetchDescriptor<CardApplication>(predicate: #Predicate { $0.id == uuid })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    // MARK: - BonusCard Merge Logic

    /// Merges a remote `BonusCard` Firestore document into the local SwiftData store.
    ///
    /// Creates a stub entry when the document arrives before the local row exists
    /// (e.g. first sync on a new device). Each field is only written when it
    /// actually differs from the local value to minimise unnecessary SwiftData
    /// dirty-tracking and UI refreshes.
    @discardableResult
    private func applyBonusCardChange(docID: String, data: [String: Any], context: ModelContext) -> Bool {
        guard let uuid = UUID(uuidString: docID) else { return false }
        let bonus: BonusCard
        var isNew = false

        if let existing = fetchBonusCard(id: docID, in: context) {
            bonus = existing
        } else {
            // Stub — real values applied immediately below.
            bonus = BonusCard(cardName: "Syncing...", bonusAmount: "")
            bonus.id = uuid
            context.insert(bonus)
            isNew = true
        }

        var changed = isNew

        // ── Core identity ──────────────────────────────────────────────────────
        if let v = data["cardName"] as? String,      v != bonus.cardName      { bonus.cardName = v;      changed = true }
        if let v = data["bonusAmount"] as? String,   v != bonus.bonusAmount   { bonus.bonusAmount = v;   changed = true }

        // Firestore stores Date as a Timestamp object; convert before comparing.
        if let ts = data["dateOpened"] as? Timestamp {
            let d = ts.dateValue()
            if d != bonus.dateOpened { bonus.dateOpened = d; changed = true }
        }

        // ── QoL fields ─────────────────────────────────────────────────────────
        if let v = data["accountHolderName"] as? String, v != bonus.accountHolderName { bonus.accountHolderName = v; changed = true }
        if let v = data["miscNotes"] as? String,          v != bonus.miscNotes          { bonus.miscNotes = v;          changed = true }

        // ── Minimum spend requirement ──────────────────────────────────────────
        if let v = data["requiresPurchases"] as? Bool,          v != bonus.requiresPurchases          { bonus.requiresPurchases = v;          changed = true }
        if let v = data["purchaseTarget"] as? Double,           v != bonus.purchaseTarget             { bonus.purchaseTarget = v;             changed = true }
        if let v = data["currentPurchaseAmount"] as? Double,    v != bonus.currentPurchaseAmount      { bonus.currentPurchaseAmount = v;      changed = true }

        // ── Direct deposit requirement ─────────────────────────────────────────
        if let v = data["requiresDirectDeposit"] as? Bool,       v != bonus.requiresDirectDeposit       { bonus.requiresDirectDeposit = v;       changed = true }
        if let v = data["directDepositTarget"] as? Double,        v != bonus.directDepositTarget         { bonus.directDepositTarget = v;         changed = true }
        if let v = data["currentDirectDepositAmount"] as? Double, v != bonus.currentDirectDepositAmount  { bonus.currentDirectDepositAmount = v;  changed = true }

        // ── Other requirement ──────────────────────────────────────────────────
        if let v = data["requiresOther"] as? Bool,      v != bonus.requiresOther      { bonus.requiresOther = v;      changed = true }
        if let v = data["otherDescription"] as? String, v != bonus.otherDescription   { bonus.otherDescription = v;   changed = true }
        if let v = data["isOtherCompleted"] as? Bool,   v != bonus.isOtherCompleted   { bonus.isOtherCompleted = v;   changed = true }

        // ── Completion flag ────────────────────────────────────────────────────
        if let v = data["isCompleted"] as? Bool, v != bonus.isCompleted { bonus.isCompleted = v; changed = true }

        return changed
    }

    // MARK: - CardApplication Merge Logic

    @discardableResult
    private func applyCardApplicationChange(docID: String, data: [String: Any], context: ModelContext) -> Bool {
        guard let uuid = UUID(uuidString: docID) else { return false }
        let app: CardApplication
        var isNew = false

        if let existing = fetchCardApplication(id: docID, in: context) {
            app = existing
        } else {
            app = CardApplication(cardName: "Syncing...", issuer: "")
            app.id = uuid
            context.insert(app)
            isNew = true
        }

        var changed = isNew

        if let v = data["cardName"] as? String,  v != app.cardName  { app.cardName = v;  changed = true }
        if let v = data["issuer"] as? String,    v != app.issuer    { app.issuer = v;    changed = true }
        if let v = data["cardType"] as? String,  v != app.cardType  { app.cardType = v;  changed = true }
        if let v = data["isApproved"] as? Bool,  v != app.isApproved { app.isApproved = v; changed = true }
        if let v = data["player"] as? String,    v != app.player    { app.player = v;    changed = true }
        if let v = data["notes"] as? String,     v != app.notes     { app.notes = v;     changed = true }

        // Numerics — Firestore may return Int or NSNumber for Double fields
        let remoteCL = (data["creditLimit"] as? Double) ?? (data["creditLimit"] as? NSNumber)?.doubleValue
        if let v = remoteCL, v != app.creditLimit { app.creditLimit = v; changed = true }

        let remoteAF = (data["annualFee"] as? Double) ?? (data["annualFee"] as? NSNumber)?.doubleValue
        if let v = remoteAF, v != app.annualFee { app.annualFee = v; changed = true }

        if let ts = data["applicationDate"] as? Timestamp {
            let d = ts.dateValue()
            if d != app.applicationDate { app.applicationDate = d; changed = true }
        }

        return changed
    }

    // MARK: - LoyaltyProgram Merge Logic

    /// Merges a remote `LoyaltyProgram` Firestore document into the local SwiftData store.
    ///
    /// Creates a stub entry when the document arrives before the local row exists
    /// (e.g. first sync on a new device). Each field is only written when it
    /// actually differs from the local value to minimise SwiftData dirty-tracking
    /// and unnecessary UI refreshes.
    @discardableResult
    private func applyLoyaltyProgramChange(docID: String, data: [String: Any], context: ModelContext) -> Bool {
        guard let uuid = UUID(uuidString: docID) else { return false }
        let program: LoyaltyProgram
        var isNew = false

        if let existing = fetchLoyaltyProgram(id: docID, in: context) {
            program = existing
        } else {
            // Stub — real values applied immediately below.
            program = LoyaltyProgram(
                programName: "Syncing...",
                category: .other,
                ownerName: "",
                gradientStartHex: "#000000",
                gradientEndHex: "#333333"
            )
            program.id = uuid
            context.insert(program)
            isNew = true
        }

        var changed = isNew

        // ── Core fields ────────────────────────────────────────────────────────
        if let v = data["programName"] as? String,     v != program.programName     { program.programName = v;     changed = true }
        if let v = data["category"] as? String,         v != program.category         { program.category = v;         changed = true }
        if let v = data["ownerName"] as? String,         v != program.ownerName         { program.ownerName = v;         changed = true }
        if let v = data["gradientStartHex"] as? String, v != program.gradientStartHex  { program.gradientStartHex = v;  changed = true }
        if let v = data["gradientEndHex"] as? String,   v != program.gradientEndHex    { program.gradientEndHex = v;    changed = true }
        // Integers from Firestore may arrive as Int or NSNumber — use the same
        // double-cast pattern as claimedAmount in applyPeriodLogChange.
        let remoteBalance = (data["pointBalance"] as? Int) ?? (data["pointBalance"] as? NSNumber)?.intValue
        if let v = remoteBalance, v != program.pointBalance { program.pointBalance = v; changed = true }

        // Firestore stores Date as a Timestamp object; convert before comparing.
        if let ts = data["lastUpdated"] as? Timestamp {
            let d = ts.dateValue()
            if d != program.lastUpdated { program.lastUpdated = d; changed = true }
        }

        // notes is optional — handle presence (set/update) and absence (clear).
        if data.keys.contains("notes") {
            let remoteNotes = data["notes"] as? String
            if remoteNotes != program.notes { program.notes = remoteNotes; changed = true }
        }

        return changed
    }
}
