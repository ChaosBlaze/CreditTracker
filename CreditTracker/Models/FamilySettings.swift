import Foundation
import SwiftData

// MARK: - FamilySettings

/// Singleton-pattern SwiftData model that stores family-wide shared preferences.
///
/// ## Singleton Contract
/// There should only ever be ONE `FamilySettings` instance per device. All queries
/// use `FetchDescriptor.fetchLimit = 1`. The Firestore document ID is pinned to
/// `Constants.familySettingsSyncID` so all family devices converge on a single
/// cloud document regardless of which device writes first.
///
/// ## Migration
/// On first creation, the initializer seeds values from the legacy `@AppStorage` /
/// UserDefaults keys so existing users don't lose their settings during the upgrade.
@Model
final class FamilySettings {

    // MARK: - Stored Properties

    var id: UUID = UUID()

    /// Whether the daily Discord Redeem Reminder notification is active.
    var discordReminderEnabled: Bool = false

    /// Hour component (0-23) of the daily reminder fire time.
    var discordReminderHour: Int = 21

    /// Minute component (0-59) of the daily reminder fire time.
    var discordReminderMinute: Int = 30

    /// FCM registration token of the device that last wrote these settings.
    ///
    /// Receiving devices compare this against their own stored FCM token
    /// (`Constants.fcmTokenKey` in UserDefaults) to determine whether a
    /// remote change was made by someone else — and therefore whether to
    /// display a "Settings Updated" banner.
    var lastModifiedByToken: String = ""

    // MARK: - Init

    init(
        discordReminderEnabled: Bool = false,
        discordReminderHour: Int = 21,
        discordReminderMinute: Int = 30,
        lastModifiedByToken: String = ""
    ) {
        self.discordReminderEnabled  = discordReminderEnabled
        self.discordReminderHour     = discordReminderHour
        self.discordReminderMinute   = discordReminderMinute
        self.lastModifiedByToken     = lastModifiedByToken
    }

    // MARK: - Migration Helper

    /// Creates a `FamilySettings` pre-populated from the legacy `@AppStorage` keys.
    ///
    /// Call this the first time FamilySettings is created so existing users
    /// keep their previously configured Discord reminder time.
    static func migratingFromAppStorage() -> FamilySettings {
        let defaults = UserDefaults.standard

        let enabled = defaults.bool(forKey: "discordReminderEnabled")

        let hour = defaults.object(forKey: "discordReminderHour") != nil
            ? defaults.integer(forKey: "discordReminderHour")
            : 21

        let minute = defaults.object(forKey: "discordReminderMinute") != nil
            ? defaults.integer(forKey: "discordReminderMinute")
            : 30

        return FamilySettings(
            discordReminderEnabled: enabled,
            discordReminderHour: hour,
            discordReminderMinute: minute
        )
    }
}
