import SwiftUI

// ── Web app URL ───────────────────────────────────────────────────────────────
let WEB_APP_BASE_URL = "http://localhost:3000"
// ─────────────────────────────────────────────────────────────────────────────

@main
struct AccuQuoteScanApp: App {

    @StateObject private var assetManager = PhotogrammetryAssetManager.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Must be registered before the app finishes launching
        PhotogrammetryAssetManager.registerBackgroundTask()
        // Trigger the download as early as possible
        Task { @MainActor in
            PhotogrammetryAssetManager.shared.prepareAsset()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(assetManager)
                .onOpenURL { _ in }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .background:
                // Schedule a BGProcessingTask so the download can continue
                // even when the app is closed or the screen is locked
                assetManager.scheduleBackgroundTaskIfNeeded()
            case .active:
                // App came back to foreground — resume polling in case
                // the background task completed the download
                assetManager.resumeForegroundPolling()
            default:
                break
            }
        }
    }
}
