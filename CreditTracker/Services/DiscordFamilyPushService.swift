import Foundation

// Sends silent FCM pushes to other family devices when Discord notification settings change.
//
// ## Why this service exists
// Firestore real-time listeners handle sync when both apps are active. But when FamilyUser2's
// app is suspended or terminated, those listeners are stopped. The only way to wake a background
// app and make it reschedule a local notification is via a silent APNs push (content-available:1).
//
// ## Architecture
// iOS App (FamilyUser1) → POST Cloud Function → FCM → APNs → AppDelegate.didReceiveRemoteNotification
// (FamilyUser2, background) → reschedule local notification
//
// ## Required setup
// Deploy CloudFunctions/index.js to your Firebase project:
//   cd CloudFunctions && npm install && firebase deploy --only functions
//
// The function name must match Constants.discordPushFunctionName ("sendFamilyDiscordPush").
final class DiscordFamilyPushService {
    static let shared = DiscordFamilyPushService()
    private init() {}

    // MARK: - Public API

    /// Notifies all other family devices that Discord notification settings changed.
    /// Call this after uploading the new FamilySettings to Firestore.
    func sendDiscordUpdate(hour: Int, minute: Int, enabled: Bool) async {
        let familyID = UserDefaults.standard.string(forKey: Constants.firestoreUserIDKey) ?? ""
        guard !familyID.isEmpty else { return }

        await callCloudFunction(payload: [
            "familyID":      familyID,
            "hour":          hour,
            "minute":        minute,
            "enabled":       enabled,
            "senderToken":   UserDefaults.standard.string(forKey: Constants.fcmTokenKey) ?? "",
            "formattedTime": timeString(hour: hour, minute: minute),
            "isTest":        false
        ])
    }

    /// Sends a test silent push to all other family devices using the current settings.
    /// Returns true when the Cloud Function accepted the request (HTTP 200).
    @discardableResult
    func sendTestPush(hour: Int, minute: Int, enabled: Bool) async -> Bool {
        let familyID = UserDefaults.standard.string(forKey: Constants.firestoreUserIDKey) ?? ""
        guard !familyID.isEmpty else { return false }

        return await callCloudFunction(payload: [
            "familyID":      familyID,
            "hour":          hour,
            "minute":        minute,
            "enabled":       enabled,
            "senderToken":   UserDefaults.standard.string(forKey: Constants.fcmTokenKey) ?? "",
            "formattedTime": timeString(hour: hour, minute: minute),
            "isTest":        true   // isTest=true includes the sender device so you can verify receipt
        ])
    }

    // MARK: - Cloud Function Caller

    @discardableResult
    private func callCloudFunction(payload: [String: Any]) async -> Bool {
        guard let projectID = firebaseProjectID() else {
            print("[DiscordFamilyPushService] PROJECT_ID missing from GoogleService-Info.plist")
            return false
        }

        // Firebase callable functions respond to HTTP POST at this standard URL.
        let endpoint = "https://us-central1-\(projectID).cloudfunctions.net/\(Constants.discordPushFunctionName)"
        guard let url = URL(string: endpoint) else { return false }

        // Firebase callable convention: wrap payload under "data" key.
        guard let body = try? JSONSerialization.data(withJSONObject: ["data": payload]) else { return false }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        do {
            let (responseData, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            if http.statusCode == 200 {
                print("[DiscordFamilyPushService] Push dispatched successfully.")
                return true
            }
            let msg = String(data: responseData, encoding: .utf8) ?? "(no body)"
            print("[DiscordFamilyPushService] Cloud Function returned \(http.statusCode): \(msg)")
            return false
        } catch {
            print("[DiscordFamilyPushService] Network error calling Cloud Function: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Helpers

    private func firebaseProjectID() -> String? {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path) else { return nil }
        return plist["PROJECT_ID"] as? String
    }

    private func timeString(hour: Int, minute: Int) -> String {
        var comps    = DateComponents()
        comps.hour   = hour
        comps.minute = minute
        guard let date = Calendar.current.date(from: comps) else {
            return "\(hour):\(String(format: "%02d", minute))"
        }
        let fmt = DateFormatter()
        fmt.timeStyle = .short
        fmt.dateStyle = .none
        return fmt.string(from: date)
    }
}
