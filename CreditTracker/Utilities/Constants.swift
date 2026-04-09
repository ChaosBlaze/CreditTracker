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
}
