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

    // MARK: - Silent Push Handler

    /// Called by iOS when a silent push (content-available: 1) arrives — even when the
    /// app is suspended or terminated.
    ///
    /// ## Prerequisites for delivery
    /// 1. `UIBackgroundModes` contains `remote-notification` in Info.plist  ✓
    /// 2. Push Notifications capability enabled → `aps-environment` in entitlements  ✓
    /// 3. The FCM payload must have `apns.payload.aps.content-available = 1`
    ///    and `apns.headers.apns-push-type = "background"` (set by the Cloud Function)
    ///
    /// ## 30-Second Budget
    /// iOS gives the app ~30 s after this delegate is called to invoke `completionHandler`.
    /// A safety-net DispatchWorkItem fires at 27 s to guarantee the budget is not exceeded
    /// even if the async Task takes unexpectedly long.
    ///
    /// ## Sender
    /// Pushes are dispatched by the `sendFamilyDiscordPush` Firebase Cloud Function,
    /// triggered by `DiscordFamilyPushService` whenever a family member changes settings.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        print("[AppDelegate] Silent push received. Keys: \(userInfo.keys.map { "\($0)" })")

        // Filter: only process our custom Discord settings update payloads.
        guard
            let type = userInfo["type"] as? String,
            type == "discordReminderUpdated"
        else {
            print("[AppDelegate] Ignoring push — type != discordReminderUpdated")
            completionHandler(.noData)
            return
        }

        // FCM data payloads are always String-valued; parse manually.
        let senderToken   = userInfo["senderToken"]   as? String ?? ""
        let formattedTime = userInfo["formattedTime"] as? String ?? ""
        let hour          = (userInfo["hour"]   as? String).flatMap(Int.init) ?? Constants.discordReminderDefaultHour
        let minute        = (userInfo["minute"] as? String).flatMap(Int.init) ?? Constants.discordReminderDefaultMinute
        let enabled       = (userInfo["enabled"] as? String) == "true"
        let myToken       = UserDefaults.standard.string(forKey: Constants.fcmTokenKey) ?? ""

        print("[AppDelegate] Discord push: hour=\(hour) minute=\(minute) enabled=\(enabled) fromSelf=\(senderToken == myToken && !myToken.isEmpty)")

        guard let container = CreditTrackerApp.sharedModelContainer else {
            print("[AppDelegate] ModelContainer not ready — skipping silent push processing.")
            completionHandler(.failed)
            return
        }

        // Safety-net: guarantee completionHandler is called within iOS's 30-second budget.
        // The Task below is fast, but this prevents a crash if something unexpected stalls.
        var handlerCalled = false
        let safetyNet = DispatchWorkItem {
            guard !handlerCalled else { return }
            handlerCalled = true
            print("[AppDelegate] Safety-net fired — calling completionHandler(.failed)")
            completionHandler(.failed)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 27, execute: safetyNet)

        Task { @MainActor in
            defer {
                safetyNet.cancel()   // Cancel safety-net once the Task completes normally.
            }

            // ── Step 1: Update local SwiftData cache ───────────────────────────
            let bgContext = ModelContext(container)

            var descriptor = FetchDescriptor<FamilySettings>()
            descriptor.fetchLimit = 1

            let settings: FamilySettings
            if let existing = try? bgContext.fetch(descriptor).first {
                settings = existing
            } else {
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
                print("[AppDelegate] Discord reminder rescheduled → \(hour):\(String(format: "%02d", minute))")
            } else {
                NotificationManager.shared.cancelDiscordReminder()
                print("[AppDelegate] Discord reminder cancelled.")
            }

            // ── Step 3: Notify the user if another device made the change ──────
            let isExternalChange = !senderToken.isEmpty && senderToken != myToken
            if isExternalChange, !formattedTime.isEmpty {
                let content   = UNMutableNotificationContent()
                content.title = "Settings Updated"
                content.body  = "Discord redeem time was changed to \(formattedTime)"
                content.sound = .default

                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "discord-settings-changed-\(UUID().uuidString)",
                    content: content,
                    trigger: trigger
                )
                try? await UNUserNotificationCenter.current().add(request)
                print("[AppDelegate] Visible alert scheduled for external change.")
            }

            guard !handlerCalled else { return }
            handlerCalled = true
            completionHandler(isExternalChange ? .newData : .noData)
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
