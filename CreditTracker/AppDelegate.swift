import UIKit
import SwiftData
import UserNotifications
import FirebaseCore
import FirebaseFirestore
import FirebaseMessaging

// MARK: - AppDelegate
//
// Registered via @UIApplicationDelegateAdaptor in CreditTrackerApp so SwiftUI's App
// lifecycle and UIKit's UIApplicationDelegate can coexist.
//
// Responsibilities:
//  • Forward APNs device tokens to Firebase Messaging (Phase 2).
//  • Save and register the FCM registration token in Firestore (Phase 2).
//  • Handle silent background pushes from our Cloud Function and reschedule
//    the Discord Reminder notification without requiring the user to open the app (Phase 3).

final class AppDelegate: NSObject, UIApplicationDelegate {

    // MARK: - App Launch

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Register for remote notifications (APNs).
        // Required even for silent pushes — iOS won't deliver content-available
        // payloads unless the app has APNs authorization.
        application.registerForRemoteNotifications()

        // Set ourselves as the FCM delegate so we receive token refreshes.
        Messaging.messaging().delegate = self

        return true
    }

    // MARK: - APNs Token Handoff

    /// APNs issued us a device token — hand it to Firebase Messaging so it can
    /// create/maintain the corresponding FCM registration token.
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Common in the Simulator — safe to ignore in production builds.
        print("[AppDelegate] APNs registration failed: \(error.localizedDescription)")
    }

    // MARK: - Silent Push Handler (Phase 3)

    /// Called by iOS when a silent push (content-available: 1) arrives.
    ///
    /// ## Thread Safety
    /// UIApplicationDelegate callbacks are dispatched on the main thread.
    /// All SwiftData operations run via `Task { @MainActor in }`, which keeps
    /// context access on the MainActor. `NotificationManager` is also @MainActor.
    ///
    /// ## 30-Second Budget
    /// iOS gives the app ~30 seconds to call `completionHandler`. The Task
    /// below is fast (one SwiftData fetch + a notification schedule), so we
    /// are well within that budget. The `completionHandler` is always called
    /// exactly once, regardless of the exit path.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Filter: only process our custom Discord settings update payloads.
        guard
            let type = userInfo["type"] as? String,
            type == "discordReminderUpdated"
        else {
            completionHandler(.noData)
            return
        }

        // Extract the strongly-typed payload fields.
        // FCM data payloads are always String-valued, so we parse manually.
        let senderToken   = userInfo["senderToken"]   as? String ?? ""
        let formattedTime = userInfo["formattedTime"] as? String ?? ""
        let hour          = (userInfo["hour"]   as? String).flatMap(Int.init) ?? Constants.discordReminderDefaultHour
        let minute        = (userInfo["minute"] as? String).flatMap(Int.init) ?? Constants.discordReminderDefaultMinute
        let enabled       = (userInfo["enabled"] as? String) == "true"

        // Our own FCM token — compare against senderToken to skip self-notifications.
        let myToken = UserDefaults.standard.string(forKey: Constants.fcmTokenKey) ?? ""

        guard let container = CreditTrackerApp.sharedModelContainer else {
            // Container unavailable — this should never happen in production but
            // we must still call the completion handler within the time budget.
            print("[AppDelegate] ModelContainer not ready — cannot process silent push.")
            completionHandler(.failed)
            return
        }

        Task { @MainActor in

            // ── Step 1: Update local SwiftData cache ───────────────────────────
            // Create an independent ModelContext so this background operation
            // doesn't interfere with any ongoing main-context transactions.
            let bgContext = ModelContext(container)

            var descriptor = FetchDescriptor<FamilySettings>()
            descriptor.fetchLimit = 1

            let settings: FamilySettings
            if let existing = try? bgContext.fetch(descriptor).first {
                settings = existing
            } else {
                // Singleton doesn't exist yet — create it from the push payload.
                settings = FamilySettings()
                bgContext.insert(settings)
            }

            settings.discordReminderEnabled = enabled
            settings.discordReminderHour    = hour
            settings.discordReminderMinute  = minute
            settings.lastModifiedByToken    = senderToken
            try? bgContext.save()

            // Mirror to UserDefaults so rescheduleAll() callers stay in sync.
            UserDefaults.standard.set(enabled, forKey: Constants.discordReminderEnabledKey)
            UserDefaults.standard.set(hour,    forKey: Constants.discordReminderHourKey)
            UserDefaults.standard.set(minute,  forKey: Constants.discordReminderMinuteKey)

            // ── Step 2: Reschedule the local notification ──────────────────────
            if enabled {
                NotificationManager.shared.scheduleDiscordReminder(hour: hour, minute: minute)
            } else {
                NotificationManager.shared.cancelDiscordReminder()
            }

            // ── Step 3: Alert the user if another device made the change ───────
            // Skip the alert if: (a) we are the sender, or (b) the payload lacks
            // a formatted time string (guard against unexpected payloads).
            let isExternalChange = !senderToken.isEmpty && senderToken != myToken
            if isExternalChange, !formattedTime.isEmpty {
                let content       = UNMutableNotificationContent()
                content.title     = "Settings Updated"
                content.body      = "Discord redeem time was changed to \(formattedTime)"
                content.sound     = .default

                // A 1-second trigger fires immediately after the app wakes,
                // even while it's still in the background.
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "discord-settings-changed-\(UUID().uuidString)",
                    content: content,
                    trigger: trigger
                )
                do {
                    try await UNUserNotificationCenter.current().add(request)
                } catch {
                    print("[AppDelegate] Failed to schedule settings-change alert: \(error)")
                }

                completionHandler(.newData)
            } else {
                // Our own write echoed back — no alert needed.
                completionHandler(isExternalChange ? .newData : .noData)
            }
        }
    }
}

// MARK: - MessagingDelegate (Phase 2)

extension AppDelegate: MessagingDelegate {

    /// Called whenever Firebase refreshes the FCM registration token.
    ///
    /// Two things happen here:
    /// 1. The token is stored in UserDefaults so SettingsView can stamp it
    ///    into `FamilySettings.lastModifiedByToken` on the next settings change.
    /// 2. The token is registered in Firestore under the family's `deviceTokens`
    ///    sub-collection so the Cloud Function can push to this device.
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }

        print("[AppDelegate] FCM token refreshed: \(String(token.prefix(20)))…")

        // 1. Persist locally.
        UserDefaults.standard.set(token, forKey: Constants.fcmTokenKey)

        // 2. Register in Firestore — skip if Firebase is not configured or the
        //    family ID hasn't been written yet (happens on very first launch).
        guard FirebaseApp.app() != nil else { return }
        let familyID = UserDefaults.standard.string(forKey: Constants.firestoreUserIDKey) ?? ""
        guard !familyID.isEmpty else { return }

        let db = Firestore.firestore()
        Task {
            do {
                // Document ID = the FCM token string itself; the Cloud Function
                // reads all docs in this collection to build the recipient list.
                try await db
                    .collection("users")
                    .document(familyID)
                    .collection("deviceTokens")
                    .document(token)
                    .setData([
                        "registeredAt": FieldValue.serverTimestamp(),
                        "platform":     "ios"
                    ], merge: true)
                print("[AppDelegate] FCM token registered in Firestore under family '\(familyID)'.")
            } catch {
                print("[AppDelegate] Failed to register FCM token: \(error.localizedDescription)")
            }
        }
    }
}
