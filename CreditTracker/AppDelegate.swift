import UIKit
import UserNotifications
import FirebaseCore
import FirebaseFirestore
import FirebaseMessaging

// MARK: - AppDelegate
//
// Registered via @UIApplicationDelegateAdaptor in CreditTrackerApp so SwiftUI's
// scene lifecycle and UIKit's UIApplicationDelegate can coexist.
//
// Responsibilities:
//  • Forward APNs device tokens to Firebase Messaging.
//  • Register the FCM token in Firestore under the family's deviceTokens collection.
//  • On silent background push: wake the Firestore listener so it re-attaches and
//    delivers the updated settings document. All SwiftData writes, notification
//    reschedules, and UserDefaults mirroring now happen in FamilySettingsRepository
//    (the single processing path — Phase 5 refactor removes the duplicate path
//    that previously lived here alongside the Firestore listener).

final class AppDelegate: NSObject, UIApplicationDelegate {

    // MARK: - App Launch

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        Messaging.messaging().delegate = self
        return true
    }

    // MARK: - APNs Token Handoff

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
        // Common in Simulator — safe to ignore in production builds.
        print("[AppDelegate] APNs registration failed: \(error.localizedDescription)")
    }

    // MARK: - Silent Push Handler

    /// Called by iOS when a silent push (content-available: 1) arrives.
    ///
    /// ## Simplified Processing Path (Phase 5)
    /// The previous implementation duplicated the FamilySettings update logic:
    ///   1. AppDelegate wrote to SwiftData and rescheduled the notification.
    ///   2. The Firestore snapshot listener (FamilySettingsRepository) did the same.
    ///
    /// The refactored path is:
    ///   1. AppDelegate wakes the Firestore listener and shows the optional
    ///      user-visible "Settings Updated" alert (requires FCM payload data).
    ///   2. FamilySettingsRepository.handleSnapshot() does everything else:
    ///      SwiftData write, UserDefaults mirror, notification reschedule.
    ///
    /// This eliminates the race condition where both paths raced to update the
    /// same SwiftData singleton and reschedule the same notification identifier.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard
            let type = userInfo["type"] as? String,
            type == "discordReminderUpdated"
        else {
            completionHandler(.noData)
            return
        }

        // Read only the fields needed for the user-visible alert.
        // All SwiftData / notification-scheduling work is handled by
        // FamilySettingsRepository when the Firestore listener fires.
        let senderToken   = userInfo["senderToken"]   as? String ?? ""
        let formattedTime = userInfo["formattedTime"] as? String ?? ""
        let myToken       = UserDefaults.standard.string(forKey: Constants.fcmTokenKey) ?? ""

        Task { @MainActor in
            // Wake the Firestore listener so it re-attaches and delivers the
            // updated settings document to FamilySettingsRepository.
            SyncCoordinator.shared.startListening()

            // Show a user-visible alert when another device changed the settings.
            // The FCM payload carries the formatted time string; Firestore does not.
            let isExternalChange = !senderToken.isEmpty && senderToken != myToken
            if isExternalChange, !formattedTime.isEmpty {
                let content       = UNMutableNotificationContent()
                content.title     = "Settings Updated"
                content.body      = "Discord redeem time was changed to \(formattedTime)"
                content.sound     = .default

                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "discord-settings-changed-\(UUID().uuidString)",
                    content:    content,
                    trigger:    trigger
                )
                do {
                    try await UNUserNotificationCenter.current().add(request)
                } catch {
                    print("[AppDelegate] Failed to schedule settings-change alert: \(error)")
                }
                completionHandler(.newData)
            } else {
                completionHandler(isExternalChange ? .newData : .noData)
            }
        }
    }
}

// MARK: - MessagingDelegate

extension AppDelegate: MessagingDelegate {

    /// Called whenever Firebase refreshes the FCM registration token.
    ///
    /// 1. Persists the token to UserDefaults for use in FamilySettings uploads.
    /// 2. Registers the token in Firestore so the Cloud Function can push to this device.
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }

        print("[AppDelegate] FCM token refreshed: \(String(token.prefix(20)))…")

        UserDefaults.standard.set(token, forKey: Constants.fcmTokenKey)

        guard FirebaseApp.app() != nil else { return }
        let familyID = UserDefaults.standard.string(forKey: Constants.firestoreUserIDKey) ?? ""
        guard !familyID.isEmpty else { return }

        Task {
            do {
                try await Firestore.firestore()
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
