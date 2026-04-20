import Foundation
import SwiftData
import FirebaseCore
import FirebaseFirestore

// MARK: - FamilySettingsRepository

/// Owns the Firestore real-time listener for the `FamilySettings` singleton document
/// and is the single authority for applying remote settings changes.
///
/// ## Responsibilities (previously split across FirestoreSyncService and AppDelegate)
/// 1. Listen to the `familySettings` Firestore collection.
/// 2. Merge remote changes into the local SwiftData `FamilySettings` singleton.
/// 3. Mirror changed values to UserDefaults for backward-compatible call sites.
/// 4. Reschedule (or cancel) the Discord Reminder notification when another device
///    updates the settings — this removes the duplicate path that previously lived
///    in AppDelegate's silent-push handler.
///
/// ## Singleton Document
/// Only the document with ID `Constants.familySettingsSyncID` is processed.
/// All other documents in the collection are silently ignored.
@MainActor
final class FamilySettingsRepository {

    private let db: Firestore
    private let userID: String
    private weak var context: ModelContext?
    private let deviceID: String
    private var listener: ListenerRegistration?

    init(db: Firestore, userID: String, context: ModelContext, deviceID: String) {
        self.db       = db
        self.userID   = userID
        self.context  = context
        self.deviceID = deviceID
    }

    func startListening() {
        guard listener == nil else { return }
        listener = collection.addSnapshotListener { [weak self] snapshot, _ in
            self?.handleSnapshot(snapshot)
        }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    private var collection: CollectionReference {
        db.collection("users").document(userID).collection("familySettings")
    }

    private func handleSnapshot(_ snapshot: QuerySnapshot?) {
        guard let snapshot, let context else { return }
        var didChange = false

        for change in snapshot.documentChanges {
            let docID = change.document.documentID

            // Only process the well-known singleton document.
            guard docID == Constants.familySettingsSyncID else { continue }

            // FamilySettings is never hard-deleted remotely.
            guard change.type == .added || change.type == .modified else { continue }
            guard !change.document.metadata.hasPendingWrites else { continue }

            let data = change.document.data()
            if data["deviceID"] as? String == deviceID, !change.document.metadata.isFromCache { continue }

            if applyChange(data: data, context: context) { didChange = true }
        }

        if didChange { try? context.save() }
    }

    @discardableResult
    private func applyChange(data: [String: Any], context: ModelContext) -> Bool {
        guard let dto = FirestoreFamilySettingsDTO(from: data) else { return false }

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

        var changed = isNew || settings.apply(dto)

        // When another device made the change, reschedule the local notification
        // and mirror to UserDefaults so zero-arg rescheduleAll() callers stay in sync.
        // This is the single processing path — AppDelegate no longer duplicates this.
        if changed && !isNew {
            let myToken = UserDefaults.standard.string(forKey: Constants.fcmTokenKey) ?? ""
            if settings.lastModifiedByToken != myToken {
                let hour    = settings.discordReminderHour
                let minute  = settings.discordReminderMinute
                let enabled = settings.discordReminderEnabled

                UserDefaults.standard.set(enabled, forKey: Constants.discordReminderEnabledKey)
                UserDefaults.standard.set(hour,    forKey: Constants.discordReminderHourKey)
                UserDefaults.standard.set(minute,  forKey: Constants.discordReminderMinuteKey)

                if enabled {
                    NotificationManager.shared.scheduleDiscordReminder(hour: hour, minute: minute)
                } else {
                    NotificationManager.shared.cancelDiscordReminder()
                }
            }
        }

        return changed
    }
}

// MARK: - FamilySettings DTO Apply

extension FamilySettings {
    @discardableResult
    func apply(_ dto: FirestoreFamilySettingsDTO) -> Bool {
        var changed = false
        if discordReminderEnabled  != dto.discordReminderEnabled  { discordReminderEnabled = dto.discordReminderEnabled;   changed = true }
        if discordReminderHour     != dto.discordReminderHour     { discordReminderHour = dto.discordReminderHour;         changed = true }
        if discordReminderMinute   != dto.discordReminderMinute   { discordReminderMinute = dto.discordReminderMinute;     changed = true }
        if lastModifiedByToken     != dto.lastModifiedByToken     { lastModifiedByToken = dto.lastModifiedByToken;         changed = true }
        return changed
    }
}
