import Foundation
import SwiftData
import FirebaseCore
import FirebaseFirestore

// MARK: - SyncCoordinator
//
// Replaces the 826-line FirestoreSyncService monolith.
//
// ## Architecture
// SyncCoordinator is a thin orchestrator: it owns the user identity, the stable
// deviceID, the collection reference helper, and the upload/delete API. All
// snapshot-handling logic is delegated to per-model Repositories, which are
// small, independently testable files focused on exactly one model type.
//
// ## Public API
// Backward-compatible with all existing call sites that used FirestoreSyncService.
// A typealias (`FirestoreSyncService = SyncCoordinator`) in the old file ensures
// zero changes are required in any view or service that calls the sync API.
//
// ## Listener Lifecycle
// startListening() activates all repositories simultaneously.
// stopListening()  removes all listeners (call on .background scene phase).
//
// ## Device ID vs. pendingUploadIDs
// The previous design tracked each local write in a Set<String> (pendingUploadIDs)
// to prevent the snapshot listener from re-applying our own writes. This required
// careful ordering around async suspension points.
//
// The new design stamps every Firestore write with a stable `deviceID`. Each
// repository's snapshot handler skips changes where `data["deviceID"] == deviceID`.
// This is stateless — no set to manage, no ordering dependency, survives restarts.

@MainActor
@Observable
final class SyncCoordinator {

    static let shared = SyncCoordinator()

    // MARK: - Observable State

    private(set) var syncState: SyncState = .idle
    private(set) var lastSyncedAt: Date? = nil

    // MARK: - Identity

    /// Stable device identifier stamped into every Firestore write.
    /// Replaces the pendingUploadIDs set — repositories skip writes where
    /// the document's deviceID matches this value.
    private let deviceID: String = {
        if let stored = UserDefaults.standard.string(forKey: "syncDeviceID") { return stored }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "syncDeviceID")
        return id
    }()

    /// Firestore path namespace for this user/family.
    /// Persisted across launches. Override with a shared family ID for cross-device sync.
    private(set) var userID: String = {
        if let stored = UserDefaults.standard.string(forKey: Constants.firestoreUserIDKey) { return stored }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: Constants.firestoreUserIDKey)
        return id
    }()

    // MARK: - Private State

    private var db: Firestore { Firestore.firestore() }
    private var modelContext: ModelContext?

    private var cardRepo: CardRepository?
    private var creditRepo: CreditRepository?
    private var periodLogRepo: PeriodLogRepository?
    private var familySettingsRepo: FamilySettingsRepository?
    private var bonusCardRepo: BonusCardRepository?
    private var loyaltyProgramRepo: LoyaltyProgramRepository?
    private var cardApplicationRepo: CardApplicationRepository?

    private init() {}

    // MARK: - Setup

    /// Configures the coordinator with the app's live model context and
    /// initialises all per-model repositories. Must be called before
    /// `startListening()` or `upload(_:)`.
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        buildRepositories(context: modelContext)
    }

    private func buildRepositories(context: ModelContext) {
        let db        = self.db
        let userID    = self.userID
        let deviceID  = self.deviceID

        cardRepo           = CardRepository(db: db, userID: userID, context: context, deviceID: deviceID)
        creditRepo         = CreditRepository(db: db, userID: userID, context: context, deviceID: deviceID)
        periodLogRepo      = PeriodLogRepository(db: db, userID: userID, context: context, deviceID: deviceID)
        familySettingsRepo = FamilySettingsRepository(db: db, userID: userID, context: context, deviceID: deviceID)
        bonusCardRepo      = BonusCardRepository(db: db, userID: userID, context: context, deviceID: deviceID)
        loyaltyProgramRepo = LoyaltyProgramRepository(db: db, userID: userID, context: context, deviceID: deviceID)
        cardApplicationRepo = CardApplicationRepository(db: db, userID: userID, context: context, deviceID: deviceID)
    }

    // MARK: - User ID Management

    /// Overrides the user ID — e.g. after Firebase Auth sign-in for cross-device sync.
    /// Tears down existing listeners and restarts them under the new Firestore path.
    func setUserID(_ id: String) {
        guard id != userID else { return }
        stopListening()
        userID = id
        UserDefaults.standard.set(id, forKey: Constants.firestoreUserIDKey)
        if let ctx = modelContext { buildRepositories(context: ctx) }
        startListening()
    }

    // MARK: - Family Sync Management

    /// Joins an existing Family Sync group using a shared family ID.
    ///
    /// 1. Stops all active listeners.
    /// 2. Wipes the local SwiftData cache to prevent mixing user data.
    /// 3. Updates local identity to the shared Family ID.
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
        UserDefaults.standard.set(true, forKey: "isFamilySyncEnabled")

        buildRepositories(context: context)
        startListening()
    }

    /// Wipes all root SwiftData models. Cascade delete rules handle children.
    private func wipeLocalData(context: ModelContext) throws {
        let cards = try context.fetch(FetchDescriptor<Card>())
        cards.forEach { context.delete($0) }

        let bonusCards = try context.fetch(FetchDescriptor<BonusCard>())
        bonusCards.forEach { context.delete($0) }

        let familySettingsItems = try context.fetch(FetchDescriptor<FamilySettings>())
        familySettingsItems.forEach { context.delete($0) }

        let loyaltyPrograms = try context.fetch(FetchDescriptor<LoyaltyProgram>())
        loyaltyPrograms.forEach { context.delete($0) }

        let cardApplications = try context.fetch(FetchDescriptor<CardApplication>())
        cardApplications.forEach { context.delete($0) }

        try context.save()
    }

    // MARK: - Listener Lifecycle

    /// Activates real-time Firestore listeners across all model repositories.
    /// Safe to call multiple times: each repository is guarded against duplicate listeners.
    func startListening() {
        guard modelContext != nil, FirebaseApp.app() != nil else { return }
        cardRepo?.startListening()
        creditRepo?.startListening()
        periodLogRepo?.startListening()
        familySettingsRepo?.startListening()
        bonusCardRepo?.startListening()
        loyaltyProgramRepo?.startListening()
        cardApplicationRepo?.startListening()
    }

    /// Removes all Firestore listeners to stop background network traffic.
    func stopListening() {
        cardRepo?.stopListening()
        creditRepo?.stopListening()
        periodLogRepo?.stopListening()
        familySettingsRepo?.stopListening()
        bonusCardRepo?.stopListening()
        loyaltyProgramRepo?.stopListening()
        cardApplicationRepo?.stopListening()
    }

    // MARK: - Upload (SwiftData → Firestore)

    /// Writes the syncable fields of any `FirestoreSyncable` model to Firestore.
    ///
    /// Always call *after* `context.save()` so local state is committed first.
    /// Uses `merge: true` to preserve any extra server-side fields.
    /// Stamps `deviceID` so snapshot listeners on this device skip the echo.
    func upload<T: FirestoreSyncable>(_ item: T) async {
        guard FirebaseApp.app() != nil else { return }
        syncState = .syncing

        var payload = item.firestorePayload()
        payload["updatedAt"] = FieldValue.serverTimestamp()
        payload["deviceID"]  = deviceID

        do {
            try await collection(for: T.self)
                .document(item.syncID)
                .setData(payload, merge: true)
            lastSyncedAt = Date()
            syncState    = .idle
        } catch {
            syncState = .error(
                SyncError.uploadFailed(id: item.syncID, underlying: error).localizedDescription
                ?? "Upload failed"
            )
        }
    }

    // MARK: - Delete (SwiftData → Firestore)

    /// Hard-deletes a single Firestore document.
    ///
    /// For Cards and Credits prefer `deleteCardCascading(_:)` and
    /// `deleteCreditCascading(_:)` which handle child documents first.
    /// Once Cloud Functions `onCardDeleted`/`onCreditDeleted` are deployed
    /// these can be swapped for soft-deletes (set `deletedAt` field only).
    func deleteDocument<T: FirestoreSyncable>(for type: T.Type, id: String) async {
        guard FirebaseApp.app() != nil else { return }
        do {
            try await collection(for: T.self).document(id).delete()
        } catch {
            print("[SyncCoordinator] Failed to delete \(T.self) document \(id): \(error.localizedDescription)")
        }
    }

    /// Safely deletes a Credit and all of its PeriodLogs from Firestore.
    /// Call this *before* `context.delete(credit)` so the relationship is intact.
    func deleteCreditCascading(_ credit: Credit) async {
        let creditID = credit.syncID
        let logIDs   = credit.periodLogs.map { $0.syncID }
        for id in logIDs { await deleteDocument(for: PeriodLog.self, id: id) }
        await deleteDocument(for: Credit.self, id: creditID)
    }

    /// Safely deletes a Card and all of its Credits + PeriodLogs from Firestore.
    /// Call this *before* `context.delete(card)` so the relationships are intact.
    func deleteCardCascading(_ card: Card) async {
        let cardID    = card.syncID
        let creditIDs = card.credits.map { $0.syncID }
        let logIDs    = card.credits.flatMap { $0.periodLogs }.map { $0.syncID }
        for id in logIDs    { await deleteDocument(for: PeriodLog.self, id: id) }
        for id in creditIDs { await deleteDocument(for: Credit.self, id: id) }
        await deleteDocument(for: Card.self, id: cardID)
    }

    // MARK: - Private Helpers

    private func collection<T: FirestoreSyncable>(for type: T.Type) -> CollectionReference {
        db.collection("users").document(userID).collection(T.firestoreCollectionName)
    }
}
