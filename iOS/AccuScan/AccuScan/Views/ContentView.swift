import SwiftUI

// MARK: - ContentView
// Root router — switches between screens based on AppState.

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            switch appState.screen {
            case .home:
                HomeView()
            case .setup:
                ScanSetupView()
            case .scanning:
                ActiveScanView()
            case .review(let session):
                ScanReviewView(session: session)
            case .export(let session):
                ExportView(session: session)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appState.screen.tag)
    }
}

extension AppState.Screen {
    var tag: Int {
        switch self {
        case .home:    return 0
        case .setup:   return 1
        case .scanning: return 2
        case .review:  return 3
        case .export:  return 4
        }
    }
}
