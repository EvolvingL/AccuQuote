import SwiftUI

// ── Web app URL ───────────────────────────────────────────────────────────────
let WEB_APP_BASE_URL = "http://localhost:3000"
// ─────────────────────────────────────────────────────────────────────────────

@main
struct AccuQuoteScanApp: App {

    @StateObject private var questionEngine = QuestionEngine.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        PhotogrammetryAssetManager.registerBackgroundTask()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(questionEngine)
                .onOpenURL { _ in }
        }
    }
}
