import SwiftUI
import RoomPlan
import ARKit
import SceneKit

// MARK: - Preparing View (shown while OTA ML asset is downloading)

struct PreparingView: View {
    @EnvironmentObject var assetManager: PhotogrammetryAssetManager
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("ACCUQUOTE")
                    .font(.custom("AvenirNext-Heavy", size: 22))
                    .kerning(4)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 60)
            .padding(.bottom, 24)

            Spacer()

            // Animated icon
            ZStack {
                Circle()
                    .stroke(Color(hex: "#3B82F6").opacity(0.15), lineWidth: 1.5)
                    .frame(width: 140, height: 140)
                    .scaleEffect(pulse ? 1.15 : 1.0)
                    .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true),
                               value: pulse)
                Circle()
                    .stroke(Color(hex: "#3B82F6").opacity(0.08), lineWidth: 1.5)
                    .frame(width: 115, height: 115)
                    .scaleEffect(pulse ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 1.6).delay(0.2).repeatForever(autoreverses: true),
                               value: pulse)
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color(hex: "#3B82F6").opacity(0.08))
                        .frame(width: 88, height: 88)
                    Image(systemName: "cpu")
                        .font(.system(size: 38, weight: .light))
                        .foregroundColor(Color(hex: "#3B82F6"))
                }
            }
            .onAppear { pulse = true }
            .padding(.bottom, 32)

            Text("Preparing AI Scanner")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.primary)
                .padding(.bottom, 12)

            Text("Downloading the AI model required for\nhigh-accuracy room scanning.")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 40)
                .padding(.bottom, 32)

            // Progress indicator
            VStack(spacing: 10) {
                ProgressView()
                    .scaleEffect(1.1)
                    .tint(Color(hex: "#3B82F6"))

                Text(progressLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .animation(.easeInOut, value: assetManager.elapsedSeconds)
            }
            .padding(.bottom, 40)

            // Requirements callout
            HStack(spacing: 8) {
                Image(systemName: "wifi")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                Text("Requires a Wi-Fi connection · One-time download")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Retry button (shown after 2 minutes with no progress)
            if assetManager.elapsedSeconds > 120 {
                Button { assetManager.retry() } label: {
                    Text("Retry Download")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color(hex: "#3B82F6"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color(hex: "#3B82F6").opacity(0.08))
                        .cornerRadius(14)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .transition(.opacity)
            }

            Text("This only happens once. Future launches are instant.")
                .font(.system(size: 12))
                .foregroundColor(Color(.tertiaryLabel))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
        }
        .background(Color(.systemBackground))
    }

    var progressLabel: String {
        let s = assetManager.elapsedSeconds
        if s < 10  { return "Starting download…" }
        if s < 60  { return "Downloading… (\(s)s)" }
        let m = s / 60; let rem = s % 60
        return "Still downloading… (\(m)m \(rem)s) — stay on Wi-Fi"
    }
}

// MARK: - Ready View

struct ReadyView: View {
    @ObservedObject var coordinator: ScanCoordinator

    var methodIcon: String {
        switch coordinator.scanMethod {
        case .lidar:          return "cube.transparent"
        case .photogrammetry: return "camera.viewfinder"
        case nil:             return "camera.viewfinder"
        }
    }

    var methodBadgeColor: Color {
        switch coordinator.scanMethod {
        case .lidar:          return Color(hex: "#22C55E")
        case .photogrammetry: return Color(hex: "#3B82F6")
        case nil:             return Color(hex: "#3B82F6")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("ACCUQUOTE")
                    .font(.custom("AvenirNext-Heavy", size: 22))
                    .kerning(4)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 60)
            .padding(.bottom, 24)

            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1.5)
                    .frame(width: 120, height: 120)
                Image(systemName: methodIcon)
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(.primary)
            }
            .padding(.bottom, 24)

            Text("Scan Space")
                .font(.system(size: 40, weight: .bold))
                .foregroundColor(.primary)
                .padding(.bottom, 12)

            HStack(spacing: 6) {
                Circle()
                    .fill(methodBadgeColor)
                    .frame(width: 8, height: 8)
                Text(coordinator.scanMethod?.displayName ?? "")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(methodBadgeColor)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(methodBadgeColor.opacity(0.1))
            .cornerRadius(20)
            .padding(.bottom, 16)

            Text(coordinator.scanMethod?.description ?? "")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 40)
                .padding(.bottom, 8)

            methodInstructions
                .padding(.horizontal, 40)

            Spacer()

            Button { coordinator.startScan() } label: {
                Text("Start Scan")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color(hex: "#FFD600"))
                    .cornerRadius(16)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            Text(deviceRequirementText)
                .font(.system(size: 12))
                .foregroundColor(Color(.tertiaryLabel))
                .padding(.bottom, 40)
        }
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    var methodInstructions: some View {
        switch coordinator.scanMethod {
        case .lidar, nil:
            EmptyView()
        case .photogrammetry:
            VStack(alignment: .leading, spacing: 8) {
                InstructionRow(icon: "1.circle.fill", text: "Walk slowly around the entire room")
                InstructionRow(icon: "2.circle.fill", text: "Keep all walls visible as you move")
                InstructionRow(icon: "3.circle.fill", text: "Good lighting gives better results")
            }
            .padding(.top, 12)
        }
    }

    var deviceRequirementText: String {
        switch coordinator.scanMethod {
        case .lidar:          return "Using LiDAR — iPhone 12 Pro or later"
        case .photogrammetry: return "Using AI depth — iPhone XS or later, iOS 17+"
        case nil:             return ""
        }
    }
}

struct InstructionRow: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.secondary)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Scanning View

struct ScanningView: View {
    @ObservedObject var coordinator: ScanCoordinator

    var body: some View {
        switch coordinator.scanMethod {
        case .lidar:
            LiDARScanningView(coordinator: coordinator)
        case .photogrammetry:
            PhotoScanningView(coordinator: coordinator)
        case nil:
            EmptyView()
        }
    }
}

// MARK: - LiDAR Scanning View

struct LiDARScanningView: View {
    @ObservedObject var coordinator: ScanCoordinator

    var body: some View {
        ZStack(alignment: .bottom) {
            if let captureView = coordinator.captureView {
                RoomCaptureViewRepresentable(captureView: captureView)
                    .ignoresSafeArea()
            }
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button { coordinator.stopScan() } label: {
                        Text("Done")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(20)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                Spacer()
                ScanProgressCard(coordinator: coordinator)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Photo/AI Scanning View

struct PhotoScanningView: View {
    @ObservedObject var coordinator: ScanCoordinator

    var body: some View {
        ZStack(alignment: .bottom) {
            if let arSession = coordinator.arSession {
                ARViewRepresentable(session: arSession)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            VStack(spacing: 0) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                        Text("\(coordinator.photoCount) frames")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(20)

                    Spacer()

                    Button { coordinator.stopScan() } label: {
                        Text("Done")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color(hex: "#FFD600").opacity(0.9))
                            .cornerRadius(20)
                    }
                    .disabled(coordinator.photoCount < 20)
                    .opacity(coordinator.photoCount < 20 ? 0.5 : 1)
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)

                Spacer()

                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 2)
                        .frame(width: 200, height: 200)
                    Circle()
                        .trim(from: 0, to: CGFloat(coordinator.scanProgress))
                        .stroke(Color(hex: "#FFD600"),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 200, height: 200)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.3), value: coordinator.scanProgress)
                    VStack(spacing: 4) {
                        Text("\(Int(coordinator.scanProgress * 100))%")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("captured")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding(.bottom, 24)

                ScanProgressCard(coordinator: coordinator)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Shared progress card

struct ScanProgressCard: View {
    @ObservedObject var coordinator: ScanCoordinator

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.2))
                    Capsule()
                        .fill(Color(hex: "#FFD600"))
                        .frame(width: geo.size.width * CGFloat(coordinator.scanProgress))
                        .animation(.easeInOut(duration: 0.4), value: coordinator.scanProgress)
                }
            }
            .frame(height: 4)

            Text(coordinator.instructionText)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.black.opacity(0.7)))
    }
}

// MARK: - Processing View

struct ProcessingView: View {
    @State private var rotation = 0.0

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            ZStack {
                Circle().stroke(Color(.systemGray5), lineWidth: 4).frame(width: 80, height: 80)
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(Color.primary, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(rotation))
                    .onAppear {
                        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                            rotation = 360
                        }
                    }
            }
            VStack(spacing: 8) {
                Text("Processing Scan")
                    .font(.system(size: 22, weight: .bold)).foregroundColor(.primary)
                Text("Calculating room dimensions…")
                    .font(.system(size: 15)).foregroundColor(.secondary)
            }
            Spacer()
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - Result View

struct ResultView: View {
    let result: RoomDimensions
    @ObservedObject var coordinator: ScanCoordinator
    @State private var sent = false

    var accuracyNote: String {
        switch result.scanMethod {
        case .lidar:          return "High precision · LiDAR"
        case .photogrammetry: return "AI depth · ±5% accuracy"
        }
    }

    var accuracyColor: Color {
        switch result.scanMethod {
        case .lidar:          return Color(hex: "#22C55E")
        case .photogrammetry: return Color(hex: "#3B82F6")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("ACCUQUOTE")
                    .font(.custom("AvenirNext-Heavy", size: 20)).kerning(4)
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24)).foregroundColor(.green)
            }
            .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 8)

            Text("Scan Complete")
                .font(.system(size: 13)).foregroundColor(.secondary)
                .padding(.horizontal, 24).frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            VStack(spacing: 0) {
                HStack {
                    Text("Room Dimensions")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary).kerning(0.5).textCase(.uppercase)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(result.roomType.capitalized)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Color(.systemGray6)).cornerRadius(8)
                        Text(accuracyNote)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(accuracyColor)
                    }
                }
                .padding(.bottom, 20)

                HStack(spacing: 16) {
                    DimensionBadge(label: "Length", value: result.lengthStr, unit: "m")
                    DimensionBadge(label: "Width",  value: result.widthStr,  unit: "m")
                    DimensionBadge(label: "Height", value: result.heightStr, unit: "m")
                }
                .padding(.bottom, 20)

                Divider().padding(.bottom, 16)

                HStack(spacing: 24) {
                    StatPill(icon: "square.fill",
                             label: "Floor area",
                             value: String(format: "%.1fm²", result.floorArea))
                    StatPill(icon: "door.left.hand.open",
                             label: "Doors",
                             value: "\(result.doorCount)")
                    StatPill(icon: "window.casement",
                             label: "Windows",
                             value: "\(result.windowCount)")
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 4)
            )
            .padding(.horizontal, 20)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    coordinator.sendResultToAccuQuote(result: result)
                    sent = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: sent ? "checkmark" : "arrow.right.circle.fill")
                            .font(.system(size: sent ? 16 : 20, weight: .bold))
                        Text(sent ? "Sent to AccuQuote" : "Send to AccuQuote")
                            .font(.system(size: 18, weight: .bold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(sent ? Color.green : Color(hex: "#FFD600"))
                    .cornerRadius(16)
                    .animation(.easeInOut(duration: 0.2), value: sent)
                }

                Button { coordinator.reset() } label: {
                    Text("Scan Again")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.systemGray6))
                        .cornerRadius(16)
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Error View

struct ErrorView: View {
    let message: String
    @ObservedObject var coordinator: ScanCoordinator

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48, weight: .light)).foregroundColor(.orange)
            VStack(spacing: 8) {
                Text("Scan Failed").font(.system(size: 22, weight: .bold))
                Text(message).font(.system(size: 15)).foregroundColor(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 32)
            }
            Spacer()
            Button { coordinator.reset() } label: {
                Text("Try Again")
                    .font(.system(size: 18, weight: .bold)).foregroundColor(.black)
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
                    .background(Color(hex: "#FFD600")).cornerRadius(16)
            }
            .padding(.horizontal, 24).padding(.bottom, 40)
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - Sub-components

struct DimensionBadge: View {
    let label: String; let value: String; let unit: String
    var body: some View {
        VStack(spacing: 6) {
            Text(label).font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                .kerning(0.5).textCase(.uppercase)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 28, weight: .bold, design: .rounded)).foregroundColor(.primary)
                Text(unit).font(.system(size: 14, weight: .medium)).foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16)
        .background(Color(.systemGray6)).cornerRadius(14)
    }
}

struct StatPill: View {
    let icon: String; let label: String; let value: String
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 16, weight: .bold)).foregroundColor(.primary)
            Text(label).font(.system(size: 11)).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - UIViewRepresentable for RoomCaptureView (LiDAR)

struct RoomCaptureViewRepresentable: UIViewRepresentable {
    let captureView: RoomCaptureView
    func makeUIView(context: Context) -> RoomCaptureView { captureView }
    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}
}

// MARK: - UIViewRepresentable for ARSession (photogrammetry)

struct ARViewRepresentable: UIViewRepresentable {
    let session: ARSession

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        view.session = session
        view.automaticallyUpdatesLighting = true
        return view
    }
    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}

// MARK: - Color extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
