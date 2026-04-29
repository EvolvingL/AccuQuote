import SwiftUI

// ── API configuration ─────────────────────────────────────────────────────────
// NOTE: rotate this key before any public release — see memory/project_pre_production_checklist.md
let ANTHROPIC_API_KEY = "YOUR_ANTHROPIC_API_KEY_HERE"
let ANTHROPIC_API_URL = "https://api.anthropic.com/v1/messages"
// Legacy — kept so QuestionEngine compiles; question gen now also calls Anthropic directly
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
