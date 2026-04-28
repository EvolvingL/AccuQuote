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
