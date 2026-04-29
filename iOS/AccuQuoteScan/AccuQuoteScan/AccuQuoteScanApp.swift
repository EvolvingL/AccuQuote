import SwiftUI

// ── API configuration ─────────────────────────────────────────────────────────
// ANTHROPIC_API_KEY is defined in APIKeys.swift (gitignored).
// Copy APIKeys.swift.example → APIKeys.swift and fill in your key.
let ANTHROPIC_API_URL = "https://api.anthropic.com/v1/messages"
// Legacy — kept so QuestionEngine compiles
let WEB_APP_BASE_URL  = "https://api.anthropic.com"
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
