import SwiftUI

// MARK: - AccuScan
// Free standalone room scanner — the trojan horse for AccuQuote.
// Scan any room, get instant measurements, export in 6 formats.
// After results → soft upsell to AccuQuote (the paid quoting tool).

@main
struct AccuScanApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
        }
    }
}
