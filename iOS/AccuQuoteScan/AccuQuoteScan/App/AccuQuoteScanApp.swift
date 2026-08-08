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
                    } else if url.scheme == "accuquote", url.host == "import" {
                        // AccuScan→AccuQuote Funnel build spec §4.2 — live
                        // deep-link path while the app is already running.
                        // The cold-launch/already-pending path is handled by
                        // ContentView's .task, which calls the same
                        // HandoffImporter.importIfPending so there's one
                        // source of truth for dedupe.
                        NotificationCenter.default.post(name: .aqHandoffDeepLink, object: url)
                    }
                }
                // Fix #14 — push permission is no longer requested here at
                // sign-in (a cold ask with no context yet). It now fires from
                // QuoteGenerationService after the user's first successful
                // quote generation, via NotificationService.
                // requestPermissionAfterFirstQuote(), which shows a primer
                // sheet first — see ContentView's showPrimerRequested handling.
                // #22: refresh entitlement when the app returns to the foreground so a
                // subscription change made elsewhere (webhook, another device) is picked
                // up without requiring a cold launch.
                .onReceive(NotificationCenter.default.publisher(
                    for: UIApplication.willEnterForegroundNotification)) { _ in
                    if authManager.isSignedIn {
                        Task { await entitlementManager.refresh() }
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
