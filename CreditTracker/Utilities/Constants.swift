import Foundation

enum Constants {
    static let bundleID = "com.shekar.CreditTracker"
    static let appGroupID = "group.com.shekar.CreditTracker"
    static let iCloudContainerID = "iCloud.com.shekar.CreditTracker"
    static let defaultReminderDays = 5
    static let minReminderDays = 1
    static let maxReminderDays = 30
    static let hasSeededDataKey = "hasSeededData"
    static let defaultReminderDaysKey = "defaultReminderDays"
    static let discordReminderEnabledKey = "discordReminderEnabled"
    static let discordReminderNotificationID = "discord-daily-reminder"
    static let discordReminderHourKey = "discordReminderHour"
    static let discordReminderMinuteKey = "discordReminderMinute"
    static let discordReminderDefaultHour = 21
    static let discordReminderDefaultMinute = 30

    // MARK: - Firestore Sync
    /// UserDefaults key for the stable user/device ID that namespaces Firestore documents.
    /// Replace the stored value with a Firebase Auth UID to enable true multi-device sync.
    static let firestoreUserIDKey = "firestoreUserID"

    // MARK: - FCM / Silent Push
    /// UserDefaults key for this device's current FCM registration token.
    /// Written by AppDelegate.MessagingDelegate; read by SettingsView to stamp
    /// `lastModifiedByToken` so receiving devices know who made a change.
    static let fcmTokenKey = "fcmDeviceToken"

    // MARK: - FamilySettings
    /// Fixed Firestore document ID for the FamilySettings singleton.
    /// All devices in a family read/write this single document, ensuring convergence.
    static let familySettingsSyncID = "family-discord-settings"

    // MARK: - Annual Fee Reminder
    /// Notification identifier prefix for annual-fee reminders.
    /// Full identifier: "annualFee_<card.id.uuidString>"
    static let annualFeeReminderPrefix = "annualFee_"
}
