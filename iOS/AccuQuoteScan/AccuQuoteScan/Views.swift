import SwiftUI
import RoomPlan

// MARK: - Ready View

struct ReadyView: View {
    @ObservedObject var coordinator: ScanCoordinator

    var body: some View {
        VStack(spacing: 0) {
            // Header
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

            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1.5)
                    .frame(width: 120, height: 120)

                Image(systemName: "cube.transparent")
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(.primary)
            }
            .padding(.bottom, 32)

            Text("Scan Space")
                .font(.system(size: 40, weight: .bold, design: .default))
                .foregroundColor(.primary)
                .padding(.bottom, 12)

            Text("Point your iPhone around the room.\nAccuQuote measures dimensions automatically\nusing LiDAR.")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 40)

            Spacer()

            // CTA
            Button {
                coordinator.startScan()
            } label: {
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

            Text("Requires iPhone 12 Pro or later")
                .font(.system(size: 12))
                .foregroundColor(Color(.tertiaryLabel))
                .padding(.bottom, 40)
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - Scanning View

struct ScanningView: View {
    @ObservedObject var coordinator: ScanCoordinator

    var body: some View {
        ZStack(alignment: .bottom) {
            // RoomPlan camera view
            if let captureView = coordinator.captureView {
                RoomCaptureViewRepresentable(captureView: captureView)
                    .ignoresSafeArea()
            }

            // Overlay
            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Spacer()
                    Button {
                        coordinator.stopScan()
                    } label: {
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

                // Bottom card
                VStack(spacing: 12) {
                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.2))
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
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.black.opacity(0.7))
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Processing View

struct ProcessingView: View {
    @State private var rotation = 0.0

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 4)
                    .frame(width: 80, height: 80)
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
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.primary)
                Text("Calculating room dimensions…")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
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

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("ACCUQUOTE")
                    .font(.custom("AvenirNext-Heavy", size: 20))
                    .kerning(4)
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.green)
            }
            .padding(.horizontal, 24)
            .padding(.top, 60)
            .padding(.bottom, 8)

            Text("Scan Complete")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            // Dimensions card
            VStack(spacing: 0) {
                HStack {
                    Text("Room Dimensions")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                        .kerning(0.5)
                        .textCase(.uppercase)
                    Spacer()
                    Text(result.roomType.capitalized)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
                .padding(.bottom, 20)

                HStack(spacing: 16) {
                    DimensionBadge(label: "Length", value: result.lengthStr, unit: "m")
                    DimensionBadge(label: "Width",  value: result.widthStr,  unit: "m")
                    DimensionBadge(label: "Height", value: result.heightStr, unit: "m")
                }
                .padding(.bottom, 20)

                Divider()
                    .padding(.bottom, 16)

                HStack(spacing: 24) {
                    StatPill(icon: "square.fill", label: "Floor area", value: String(format: "%.1fm²", result.floorArea))
                    StatPill(icon: "door.left.hand.open", label: "Doors", value: "\(result.doorCount)")
                    StatPill(icon: "window.casement", label: "Windows", value: "\(result.windowCount)")
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

            // Send to AccuQuote
            VStack(spacing: 12) {
                Button {
                    coordinator.sendResultToAccuQuote(result: result)
                    sent = true
                } label: {
                    HStack(spacing: 10) {
                        if sent {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .bold))
                            Text("Sent to AccuQuote")
                                .font(.system(size: 18, weight: .bold))
                        } else {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 20))
                            Text("Send to AccuQuote")
                                .font(.system(size: 18, weight: .bold))
                        }
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(sent ? Color.green : Color(hex: "#FFD600"))
                    .cornerRadius(16)
                    .animation(.easeInOut(duration: 0.2), value: sent)
                }

                Button {
                    coordinator.reset()
                } label: {
                    Text("Scan Again")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.systemGray6))
                        .cornerRadius(16)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
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
                .font(.system(size: 48, weight: .light))
                .foregroundColor(.orange)

            VStack(spacing: 8) {
                Text("Scan Failed")
                    .font(.system(size: 22, weight: .bold))
                Text(message)
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            Button {
                coordinator.reset()
            } label: {
                Text("Try Again")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color(hex: "#FFD600"))
                    .cornerRadius(16)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - Sub-components

struct DimensionBadge: View {
    let label: String
    let value: String
    let unit: String

    var body: some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .kerning(0.5)
                .textCase(.uppercase)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text(unit)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(.systemGray6))
        .cornerRadius(14)
    }
}

struct StatPill: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.primary)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - UIViewRepresentable for RoomCaptureView

struct RoomCaptureViewRepresentable: UIViewRepresentable {
    let captureView: RoomCaptureView

    func makeUIView(context: Context) -> RoomCaptureView {
        captureView
    }
    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}
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
