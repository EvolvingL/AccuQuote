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

    init() {
        // Trigger the OTA ML asset download as early as possible — before
        // the first frame renders — so the download starts immediately on launch.
        Task { @MainActor in
            PhotogrammetryAssetManager.shared.prepareAsset()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(assetManager)
                .onOpenURL { _ in
                    // Deep link handler: accuquote://scan
                }
        }
    }
}
