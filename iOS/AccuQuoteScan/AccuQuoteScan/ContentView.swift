import SwiftUI

// Threshold below which we prompt for quick-setup before generating a quote
let profileQuickSetupThreshold = 50

struct ContentView: View {
    @StateObject private var coordinator = ScanCoordinator()
    @EnvironmentObject var questionEngine: QuestionEngine

    // Guest mode: bypasses profile, goes straight to scan-only flow
    @State private var showGuest = false

    var body: some View {
        ZStack {
            if showGuest {
                // ── Guest / free tool flow ──────────────────────────────
                GuestLandingView(showGuest: $showGuest)
                    .transition(.move(edge: .trailing).combined(with: .opacity))

            } else {
                // ── Full app flow (no gate) ──────────────────────────────
                switch coordinator.state {
                case .ready:
                    ReadyView(coordinator: coordinator, onGuestTap: { showGuest = true })
                case .scanning:
                    ScanningView(coordinator: coordinator)
                case .processing:
                    ProcessingView()
                case .complete(let result):
                    ResultView(result: result, coordinator: coordinator)
                case .error(let message):
                    ErrorView(message: message, coordinator: coordinator)
                }
            }
        }
        .animation(.easeInOut(duration: 0.4), value: showGuest)
        .preferredColorScheme(.light)
    }
}
