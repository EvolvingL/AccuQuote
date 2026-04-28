import SwiftUI
import RoomPlan

struct ContentView: View {
    @StateObject private var coordinator = ScanCoordinator()
    @EnvironmentObject var assetManager: PhotogrammetryAssetManager

    var body: some View {
        ZStack {
            // Non-LiDAR device and AI model not yet ready — block scanning
            if coordinator.scanMethod == nil {
                PreparingView()
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
        .preferredColorScheme(.light)
        // When the asset finishes downloading, coordinator.scanMethod becomes
        // non-nil and the ZStack re-evaluates automatically via @Published.
        .onChange(of: assetManager.assetState) { newState in
            if newState == .ready {
                coordinator.reset()  // pick up the now-available scan method
            }
        }
    }
}
