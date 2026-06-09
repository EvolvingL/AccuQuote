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
                // Light mode to match AccuQuote — both apps share the same light,
                // document-style chrome. The only intentionally dark surface is the
                // live-scanning HUD, which overlays the camera feed and keeps its own
                // explicit dark/glass treatment (so the coverage ring and instructions
                // stay legible over the viewfinder).
                .preferredColorScheme(.light)
                .tint(AS.lightBlue)   // consistent system-blue accent, matches AQ.blue
        }
    }
}
