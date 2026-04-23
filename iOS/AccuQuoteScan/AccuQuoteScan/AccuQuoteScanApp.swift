import SwiftUI

@main
struct AccuQuoteScanApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    // Deep link handler: accuquote://scan
                    // The ContentView observes ScanCoordinator so no extra work needed here
                }
        }
    }
}
