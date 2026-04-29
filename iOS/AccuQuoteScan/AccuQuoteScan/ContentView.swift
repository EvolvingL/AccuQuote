import SwiftUI

// Minimum personalisation % before scanning is unlocked
let profileUnlockThreshold = 70

struct ContentView: View {
    @StateObject private var coordinator = ScanCoordinator()
    @EnvironmentObject var questionEngine: QuestionEngine

    var profileReady: Bool { questionEngine.personalisation >= profileUnlockThreshold }

    var body: some View {
        ZStack {
            if !profileReady {
                ProfileGateView()
                    .transition(.opacity)
            } else {
                switch coordinator.state {
                case .ready:
                    ReadyView(coordinator: coordinator)
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
        .animation(.easeInOut(duration: 0.4), value: profileReady)
        .preferredColorScheme(.light)
    }
}
