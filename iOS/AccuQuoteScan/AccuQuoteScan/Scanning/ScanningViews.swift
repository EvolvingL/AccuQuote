import SwiftUI

// MARK: - Scanning View

struct ScanningView: View {
    @ObservedObject var coordinator: ScanCoordinator
    var body: some View {
        switch coordinator.scanMethod {
        case .lidar:      LiDARScanningView(coordinator: coordinator)
        case .poseFusion: PoseFusionScanningView(coordinator: coordinator)
        case .manual:     EmptyView()  // manual never enters .scanning state
        }
    }
}

// MARK: - LiDAR Scanning View

struct LiDARScanningView: View {
    @ObservedObject var coordinator: ScanCoordinator
    var body: some View {
        LiDARHostRepresentable(coordinator: coordinator)
            .ignoresSafeArea()
    }
}

// MARK: - Pose Fusion Scanning View

struct PoseFusionScanningView: View {
    @ObservedObject var coordinator: ScanCoordinator
    @ObservedObject private var tracker: ScanCoverageTracker
    @State private var pulsing = false
    @State private var showTutorial = !UserDefaults.standard.bool(forKey: "aq_posefusion_tutorial_seen")

    init(coordinator: ScanCoordinator) {
        self.coordinator = coordinator
        self.tracker = coordinator.coverageTracker
    }

    // Bright vivid blue for the scanning indicator
    private let scanBlue = Color(red: 0.20, green: 0.60, blue: 1.00)

    var body: some View {
        ZStack(alignment: .bottom) {
            if coordinator.arSession != nil {
                ARHostRepresentable(coordinator: coordinator).ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    // Pulsing "Scanning" status pill
                    HStack(spacing: 7) {
                        Circle()
                            .fill(scanBlue)
                            .frame(width: 9, height: 9)
                            .shadow(color: scanBlue.opacity(pulsing ? 0.9 : 0.2), radius: pulsing ? 8 : 2)
                            .scaleEffect(pulsing ? 1.35 : 0.85)
                            .animation(
                                .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                                value: pulsing
                            )
                        Text("Scanning")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .opacity(pulsing ? 1.0 : 0.55)
                            .animation(
                                .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                                value: pulsing
                            )
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(scanBlue.opacity(pulsing ? 0.28 : 0.12))
                    .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulsing)
                    .cornerRadius(22)
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(scanBlue.opacity(0.5), lineWidth: 1))
                    Spacer()
                    Button { coordinator.stopScan() } label: {
                        Text("Done")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(.ultraThinMaterial).cornerRadius(18)
                    }
                    .opacity(tracker.coverage >= 0.80 ? 1.0 : 0.55)
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)

                Spacer()

                // Instruction text above the ring
                Text(coordinator.instructionText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 16)

                // Coverage ring — always visible during scan
                CoverageRingView(
                    sectors:    tracker.sectors,
                    coverage:   tracker.coverage,
                    isComplete: tracker.isComplete
                )
                .padding(.bottom, 20)

                ScanHUD(coordinator: coordinator)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 48)
            }
        }
        .ignoresSafeArea()
        .onAppear { pulsing = true }
        .overlay {
            if showTutorial {
                ZStack {
                    Color.black.opacity(0.55).ignoresSafeArea()
                    ScanTutorialAnimation()
                        .padding(.bottom, 140)
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation(.easeOut(duration: 0.4)) { showTutorial = false }
                        UserDefaults.standard.set(true, forKey: "aq_posefusion_tutorial_seen")
                    }
                }
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.3)) { showTutorial = false }
                    UserDefaults.standard.set(true, forKey: "aq_posefusion_tutorial_seen")
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showTutorial)
    }
}

// MARK: - Scan Tutorial Animation

private struct ScanTutorialAnimation: View {
    @State private var sweepOffset: CGFloat = -40
    @State private var sweepOpacity: Double = 0

    var body: some View {
        VStack(spacing: 28) {
            ZStack {
                // Sweep arcs
                ForEach(0..<3) { i in
                    Capsule()
                        .fill(Color.white.opacity(0.15 - Double(i) * 0.04))
                        .frame(width: 3, height: 40 + CGFloat(i) * 16)
                        .offset(x: sweepOffset + CGFloat(i) * 6)
                        .animation(
                            .easeInOut(duration: 1.4).repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.08),
                            value: sweepOffset
                        )
                }
                // Phone icon
                Image(systemName: "iphone")
                    .font(.system(size: 48, weight: .ultraLight))
                    .foregroundColor(.white)
                    .rotationEffect(.degrees(90))
                    .offset(x: sweepOffset)
                    .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: sweepOffset)
            }
            .frame(width: 160, height: 100)
            .opacity(sweepOpacity)

            VStack(spacing: 8) {
                Text("Move around the room")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                    Text("Cover every wall, ceiling and floor")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .onAppear {
            withAnimation(.easeIn(duration: 0.4)) { sweepOpacity = 1 }
            sweepOffset = 40
        }
    }
}

// MARK: - Scan HUD (shared bottom card)

struct ScanHUD: View {
    @ObservedObject var coordinator: ScanCoordinator
    var body: some View {
        VStack(spacing: 10) {
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15))
                    Capsule()
                        .fill(Color.white)
                        .frame(width: geo.size.width * CGFloat(coordinator.scanProgress))
                        .animation(.easeInOut(duration: 0.4), value: coordinator.scanProgress)
                }
            }
            .frame(height: 3)
            Text(coordinator.instructionText)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.black.opacity(0.55))
                .background(.ultraThinMaterial)
                .cornerRadius(18)
        )
    }
}

// MARK: - Processing View

struct ProcessingView: View {
    @State private var rotation = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion   // #11

    var body: some View {
        VStack(spacing: 0) {

            Spacer()

            // Spinner — uses a system ProgressView when Reduce Motion is on so there's
            // no continuously spinning element (#11)
            if reduceMotion {
                ProgressView()
                    .controlSize(.large)
                    .tint(AQ.blue)
                    .padding(.bottom, 32)
            } else {
                ZStack {
                    Circle()
                        .stroke(AQ.rule, lineWidth: 1.5)
                        .frame(width: 64, height: 64)
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(AQ.blue, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .frame(width: 64, height: 64)
                        .rotationEffect(.degrees(rotation))
                        .onAppear {
                            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                                rotation = 360
                            }
                        }
                }
                .padding(.bottom, 32)
            }

            Text("Processing Scan")
                .font(.title2.weight(.semibold))   // #1
                .foregroundColor(AQ.ink)
                .padding(.bottom, 8)
            Text("Calculating dimensions…")
                .font(AQ.body(15))
                .foregroundColor(AQ.secondary)

            Spacer()
        }
        .background(Color.white)
    }
}
