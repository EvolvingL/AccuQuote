import SwiftUI

// ── Web app URL ───────────────────────────────────────────────────────────────
// Change this one constant to switch between local dev and production.
// Local testing:  "http://localhost:3000"   (run: node server/index.js)
// Render staging: "https://accuquote-YOURNAME.onrender.com"
// Production:     "https://accuquote.co.uk"  (once custom domain is set)
let WEB_APP_BASE_URL = "http://localhost:3000"
// ─────────────────────────────────────────────────────────────────────────────

@main
struct AccuQuoteScanApp: App {

    @StateObject private var assetManager = PhotogrammetryAssetManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(assetManager)
                .onAppear {
                    // Kick off OTA asset download in the background.
                    // On first launch this triggers iOS to fetch the ML model.
                    // On subsequent launches it returns immediately if already ready.
                    assetManager.prepareAsset()
                }
                .onOpenURL { _ in
                    // Deep link handler: accuquote://scan
                    // ContentView observes ScanCoordinator — no extra work needed
                }
        }
    }
}
