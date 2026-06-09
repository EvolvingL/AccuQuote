import UIKit
import UserNotifications

// MARK: - NotificationService
//
// Handles the full APNs / FCM push notification lifecycle:
//   1. Requests permission from the user
//   2. Receives the APNs device token from iOS
//   3. Uploads that token to the AccuQuote server (POST /api/push/register)
//      along with uid, tier, trade, and quoteCount so the server can target
//      and personalise notifications without any extra queries
//   4. Handles foreground notification presentation (shows banner + sound)
//
// The FCM token exchange is handled server-side: the server stores the raw
// APNs token and uses Firebase Admin SDK's messaging() API to send via FCM.
// This means NO Firebase SDK is required on the iOS side.

@MainActor
final class NotificationService: NSObject, ObservableObject {

    static let shared = NotificationService()

    @Published private(set) var permissionGranted: Bool = false
    @Published private(set) var lastReceivedNotification: ReceivedNotification? = nil

    private override init() { super.init() }

    // MARK: - Permission request
    // Call once after sign-in. Safe to call multiple times — iOS deduplicates.

    func requestPermission() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { [weak self] granted, _ in
            Task { @MainActor in
                self?.permissionGranted = granted
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    // MARK: - Token registration
    // Called from AppDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)
    // via AccuQuoteScanApp. Uploads the token plus user context to the server.

    func didRegisterToken(_ deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task {
            await uploadToken(tokenString)
        }
    }

    func didFailToRegisterToken(_ error: Error) {
        print("[Push] APNs registration failed: \(error.localizedDescription)")
    }

    // MARK: - Token upload

    private func uploadToken(_ token: String) async {
        guard let idToken = await AuthManager.shared.currentIdToken() else { return }

        let uid       = AuthManager.shared.userId
        let trade     = UserDefaults.standard.string(forKey: "aq_trade") ?? "general"
        let quoteCount = UserDefaults.standard.integer(forKey: "aq_total_quotes")

        var request = URLRequest(url: URL(string: "\(AQBackend.baseURL)/api/push/register")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "token":      token,
            "uid":        uid,
            "trade":      trade,
            "quoteCount": quoteCount,
            "platform":   "ios",
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                // Fix #17: store APNs token in Keychain, not UserDefaults —
                // UserDefaults is unencrypted on disk; Keychain is hardware-backed.
                SecureTokenStore.write(key: "aq_apns_token", value: token)
            }
        } catch {
            print("[Push] Token upload failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Update server metadata
    // Call when quoteCount or trade changes so personalised pushes stay accurate.

    func syncMetadata(quoteCount: Int, trade: String) {
        // Fix #18: trade/quoteCount are now fetched server-side from Firestore in
        // /api/push/register, so these local values are only kept as a hint for
        // token-rotation detection — the server ignores them from the client.
        UserDefaults.standard.set(quoteCount, forKey: "aq_total_quotes")
        UserDefaults.standard.set(trade, forKey: "aq_trade")
        guard let storedToken = SecureTokenStore.read(key: "aq_apns_token"),
              !storedToken.isEmpty else { return }
        Task { await uploadToken(storedToken) }
    }
}

// MARK: - UNUserNotificationCenterDelegate
// Shows notifications as banners even when the app is in the foreground.

extension NotificationService: UNUserNotificationCenterDelegate {

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let title    = response.notification.request.content.title
        let body     = response.notification.request.content.body
        let deepLink = userInfo["deep_link"] as? String

        Task { @MainActor in
            self.lastReceivedNotification = ReceivedNotification(
                title: title, body: body, deepLink: deepLink, userInfo: userInfo
            )
        }
        completionHandler()
    }
}

// MARK: - ReceivedNotification

struct ReceivedNotification {
    let title:    String
    let body:     String
    let deepLink: String?
    let userInfo: [AnyHashable: Any]
}
