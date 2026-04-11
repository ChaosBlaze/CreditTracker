import Foundation
import UserNotifications
internal import Combine

@MainActor
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - Foreground presentation

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func requestPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            )
            await checkStatus()
            if !granted {
                print("Notification permission denied")
            }
        } catch {
            print("Notification permission error: \(error)")
        }
    }

    func checkStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    // MARK: - Schedule per-credit reminder

    func scheduleReminder(for credit: Credit, periodEnd: Date) {
        guard credit.customReminderEnabled else { return }

        // Capture values before async work to avoid SwiftData model access off @MainActor
        let creditName = credit.name
        let cardName = credit.card?.name ?? "your card"
        let reminderDays = credit.reminderDaysBefore
        let identifier = credit.id.uuidString

        let reminderDate = Calendar.current.date(
            byAdding: .day,
            value: -reminderDays,
            to: periodEnd
        ) ?? periodEnd

        guard reminderDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Credit Reminder"
        content.body = "Your \(creditName) on \(cardName) expires in \(reminderDays) days – don't forget to use it!"
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: reminderDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Failed to schedule notification for \(creditName): \(error)")
            }
        }
    }

    // MARK: - Cancel per-credit reminder

    func cancelReminder(for credit: Credit) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [credit.id.uuidString]
        )
    }

    // MARK: - Reschedule all reminders

    func rescheduleAll(credits: [Credit]) {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        for credit in credits {
            if let activePeriod = PeriodEngine.activePeriodLog(for: credit) {
                if activePeriod.periodStatus == .pending || activePeriod.periodStatus == .partiallyClaimed {
                    scheduleReminder(for: credit, periodEnd: activePeriod.periodEnd)
                }
            }
        }
        // Restore the discord reminder if it was enabled — removeAll wipes it too
        if UserDefaults.standard.bool(forKey: Constants.discordReminderEnabledKey) {
            scheduleDiscordReminder()
        }
    }

    // MARK: - Discord daily reminder

    /// Schedules the daily Discord Redeem reminder using explicit `hour`/`minute` values.
    ///
    /// Prefer this overload when the source of truth is `FamilySettings` (via the
    /// Firestore sync path or the background push handler) to avoid any race between
    /// SwiftData model changes and UserDefaults propagation.
    func scheduleDiscordReminder(hour: Int, minute: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Discord Reminder"
        content.body  = "Redeem Giftcard"
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(hour: hour, minute: minute),
            repeats: true
        )
        let request = UNNotificationRequest(
            identifier: Constants.discordReminderNotificationID,
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error { print("Failed to schedule discord reminder: \(error)") }
        }
    }

    /// Zero-argument variant — reads hour/minute from UserDefaults (legacy path).
    /// Kept for `rescheduleAll()` backward compatibility. Prefer the explicit overload
    /// when scheduling from `FamilySettings`.
    func scheduleDiscordReminder() {
        let content = UNMutableNotificationContent()
        content.title = "Discord Reminder"
        content.body = "Redeem Giftcard"
        content.sound = .default

        let defaults = UserDefaults.standard
        let hour = defaults.object(forKey: Constants.discordReminderHourKey) != nil
            ? defaults.integer(forKey: Constants.discordReminderHourKey)
            : Constants.discordReminderDefaultHour
        let minute = defaults.object(forKey: Constants.discordReminderMinuteKey) != nil
            ? defaults.integer(forKey: Constants.discordReminderMinuteKey)
            : Constants.discordReminderDefaultMinute

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(hour: hour, minute: minute),
            repeats: true
        )
        let request = UNNotificationRequest(
            identifier: Constants.discordReminderNotificationID,
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error { print("Failed to schedule discord reminder: \(error)") }
        }
    }

    func cancelDiscordReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [Constants.discordReminderNotificationID]
        )
    }

    // MARK: - Payment reminders

    func schedulePaymentReminder(for card: Card) {
        guard card.paymentReminderEnabled, let dueDay = card.paymentDueDay else { return }

        let cardName = card.name
        let daysBefore = card.paymentReminderDaysBefore
        let identifier = "payment_\(card.id.uuidString)"
        let reminderDay = max(1, dueDay - daysBefore)

        let content = UNMutableNotificationContent()
        content.title = "💳 Payment Due Soon"
        content.body = "Your \(cardName) payment is due in \(daysBefore) days. Don't forget to pay!"
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(day: reminderDay, hour: 9, minute: 0),
            repeats: true
        )
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error { print("Failed to schedule payment reminder for \(cardName): \(error)") }
        }
    }

    func cancelPaymentReminder(for card: Card) {
        let identifier = "payment_\(card.id.uuidString)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func rescheduleAllPaymentReminders(cards: [Card]) {
        let identifiers = cards.map { "payment_\($0.id.uuidString)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        for card in cards {
            schedulePaymentReminder(for: card)
        }
    }

    // MARK: - Test notification

    func scheduleTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Test Successful"
        content.body = "Your notifications are working perfectly."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
        let request = UNNotificationRequest(
            identifier: "test-notification-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error { print("Failed to schedule test notification: \(error)") }
        }
    }
}
