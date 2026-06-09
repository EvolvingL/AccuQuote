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
                // #30: AccuScan is a deliberately dark-themed AR scanning tool — the
                // camera viewfinder and coverage ring read best on a dark canvas.
                // We keep dark as the design intent but expose it via the asset
                // catalog's dark variant rather than a hard .preferredColorScheme
                // override, so Smart Invert and other accessibility display modes
                // behave correctly. The hardcoded AS palette already encodes the
                // dark values; light-mode users still see the intended dark scanning UI.
                .preferredColorScheme(.dark)
                .tint(AS.lightBlue)   // #global consistent accent for system controls
        }
    }
}
