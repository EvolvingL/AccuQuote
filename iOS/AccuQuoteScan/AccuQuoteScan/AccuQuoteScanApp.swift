import SwiftUI

@main
struct AccuQuoteScanApp: App {

    @StateObject private var questionEngine   = QuestionEngine.shared
    @StateObject private var authManager      = AuthManager.shared
    @StateObject private var entitlementManager = EntitlementManager.shared

    init() {
        PhotogrammetryAssetManager.registerBackgroundTask()
    }

    var body: some Scene {
        WindowGroup {
            AuthGateView()
                .environmentObject(questionEngine)
                .environmentObject(authManager)
                .environmentObject(entitlementManager)
                .onOpenURL { url in
                    // Handle accuquote://stripe-return after Stripe checkout
                    if url.scheme == "accuquote", url.host == "stripe-return" {
                        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                        let status = components?.queryItems?.first(where: { $0.name == "status" })?.value
                        if status == "success" {
                            // Refresh entitlement — webhook may take a moment
                            Task {
                                try? await Task.sleep(nanoseconds: 2_000_000_000)
                                await EntitlementManager.shared.refresh()
                            }
                        }
                    }
                }
        }
    }
}
