import SwiftUI
import RoomPlan

struct ContentView: View {
    @StateObject private var coordinator = ScanCoordinator()

    var body: some View {
        ZStack {
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
        .preferredColorScheme(.light)
    }
}
