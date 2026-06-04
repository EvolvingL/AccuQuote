import SwiftUI
import UIKit

// MARK: - App entry point
// @UIApplicationDelegateAdaptor is required to receive APNs device token
// callbacks — there is no SwiftUI-native equivalent for these two methods.

@main
struct AccuQuoteScanApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var questionEngine      = QuestionEngine.shared
    @StateObject private var authManager         = AuthManager.shared
    @StateObject private var entitlementManager  = EntitlementManager.shared
    @StateObject private var notificationService = NotificationService.shared

    init() {
        PhotogrammetryAssetManager.registerBackgroundTask()
    }

    var body: some Scene {
        WindowGroup {
            AuthGateView()
                .environmentObject(questionEngine)
                .environmentObject(authManager)
                .environmentObject(entitlementManager)
                .environmentObject(notificationService)
                .onOpenURL { url in
                    // Handle accuquote://stripe-return after Stripe checkout
                    if url.scheme == "accuquote", url.host == "stripe-return" {
                        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                        let status = components?.queryItems?.first(where: { $0.name == "status" })?.value
                        if status == "success" {
                            Task {
                                try? await Task.sleep(nanoseconds: 2_000_000_000)
                                await EntitlementManager.shared.refresh()
                            }
                        }
                    }
                }
                // Request push permission once after the user signs in
                .onChange(of: authManager.isSignedIn) { signedIn in
                    if signedIn {
                        NotificationService.shared.requestPermission()
                    }
                }
        }
    }
}

// MARK: - AppDelegate
// Receives APNs token callbacks from iOS and forwards to NotificationService.

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            NotificationService.shared.didRegisterToken(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            NotificationService.shared.didFailToRegisterToken(error)
        }
    }
}
