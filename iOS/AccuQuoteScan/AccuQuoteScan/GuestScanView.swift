import SwiftUI
import UIKit

// MARK: - Guest Scan Flow
//
// Zero-friction entry point. No profile required. No quote generation.
// User scans a room → gets a shareable results card → soft upsell to full app.
//
// Designed as a viral free tool: the result card is visually impressive,
// personal, and easy to screenshot + share.

// MARK: - Guest Entry (landing screen before scan)

struct GuestLandingView: View {
    @Binding var showGuest: Bool
    @StateObject private var coordinator = ScanCoordinator()

    var body: some View {
        ZStack {
            switch coordinator.state {
            case .ready:
                GuestReadyView(coordinator: coordinator, showGuest: $showGuest)
            case .scanning:
                ScanningView(coordinator: coordinator)
            case .processing:
                ProcessingView()
            case .complete(let result):
                GuestResultView(result: result, coordinator: coordinator, showGuest: $showGuest)
            case .error(let message):
                GuestErrorView(message: message, coordinator: coordinator)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: coordinator.stateTag)
    }
}

// MARK: - Guest Ready Screen

struct GuestReadyView: View {
    @ObservedObject var coordinator: ScanCoordinator
    @Binding var showGuest: Bool

    private let navy = Color(red: 0.06, green: 0.07, blue: 0.13)
    private let gold = Color(red: 0.784, green: 0.573, blue: 0.165)

    var isLiDAR: Bool { coordinator.scanMethod == .lidar }

    var body: some View {
        ZStack {
            navy.ignoresSafeArea()

            VStack(spacing: 0) {
                // Nav bar
                HStack {
                    Button {
                        showGuest = false
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    Spacer()
                    AQLogoView()
                    Spacer()
                    // Balance the back button
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.clear)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 16)

                Spacer()

                VStack(spacing: 20) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(gold.opacity(0.12))
                            .frame(width: 88, height: 88)
                        Image(systemName: isLiDAR ? "dot.scope" : "camera.viewfinder")
                            .font(.system(size: 36))
                            .foregroundColor(gold)
                    }

                    VStack(spacing: 10) {
                        Text("Room Scanner")
                            .font(.system(size: 30, weight: .bold, design: .default))
                            .foregroundColor(.white)

                        Text("Scan any room in seconds.\nGet instant, accurate measurements — free.")
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.55))
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                    }

                    // Accuracy badge
                    HStack(spacing: 6) {
                        Circle()
                            .fill(isLiDAR ? Color(hex: "#22C55E") : Color(hex: "#3B82F6"))
                            .frame(width: 7, height: 7)
                        Text(isLiDAR ? "LiDAR precision · ±1cm" : "Camera sweep · ±5–10cm")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
                }

                Spacer()

                VStack(spacing: 12) {
                    // Primary CTA
                    Button {
                        coordinator.startScan()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: isLiDAR ? "dot.scope" : "camera.viewfinder")
                                .font(.system(size: 18, weight: .semibold))
                            Text(isLiDAR ? "Start LiDAR Scan" : "Sweep Room")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(gold)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    Text("No sign-up. No profile needed. Just scan.")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.3))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 36)
            }
        }
    }
}

// MARK: - Guest Result Card

struct GuestResultView: View {
    let result: RoomDimensions
    @ObservedObject var coordinator: ScanCoordinator
    @Binding var showGuest: Bool

    @State private var showShareSheet = false
    @State private var shareImage: UIImage?
    @State private var roomLabel: String = "Room"
    @State private var showUpsell = false

    private let navy = Color(red: 0.06, green: 0.07, blue: 0.13)
    private let gold = Color(red: 0.784, green: 0.573, blue: 0.165)

    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                // Nav
                HStack {
                    Button {
                        coordinator.reset()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Scan again")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(gold)
                    }
                    Spacer()
                    AQLogoView()
                    Spacer()
                    Button {
                        renderShareCard()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Share")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(gold)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color(UIColor.systemBackground))
                .overlay(
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(Color(UIColor.separator)),
                    alignment: .bottom
                )

                ScrollView {
                    VStack(spacing: 20) {

                        // Result card (also rendered for share)
                        GuestResultCard(result: result, roomLabel: roomLabel, gold: gold, navy: navy)
                            .padding(.top, 20)
                            .padding(.horizontal, 20)

                        // Room label input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Room name (optional)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 20)

                            TextField("e.g. Living room, Master bedroom...", text: $roomLabel)
                                .font(.system(size: 15))
                                .padding(14)
                                .background(Color(UIColor.systemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .padding(.horizontal, 20)
                        }

                        // Share button
                        Button {
                            renderShareCard()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 17, weight: .semibold))
                                Text("Share your scan result")
                                    .font(.system(size: 17, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(navy)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .padding(.horizontal, 20)
                        }

                        Color.clear.frame(height: 20)
                    }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let img = shareImage {
                ShareSheet(items: [img])
            }
        }
        .sheet(isPresented: $showUpsell) {
            GuestUpsellSheet(gold: gold, navy: navy, showGuest: $showGuest)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                showUpsell = true
            }
        }
    }

    // Renders the result card to a UIImage for sharing
    private func renderShareCard() {
        let cardView = GuestShareCard(result: result, roomLabel: roomLabel, gold: gold, navy: navy)
            .frame(width: 390, height: 520)
        let renderer = ImageRenderer(content: cardView)
        renderer.scale = 3.0
        shareImage = renderer.uiImage
        showShareSheet = true
    }
}

// MARK: - The shareable result card (shown in-app and rendered for Share Sheet)

struct GuestResultCard: View {
    let result: RoomDimensions
    let roomLabel: String
    let gold: Color
    let navy: Color

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(roomLabel.isEmpty ? result.roomType : roomLabel)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(result.scanMethod == .lidar ? Color(hex: "#22C55E") : Color(hex: "#3B82F6"))
                            .frame(width: 6, height: 6)
                        Text(result.scanMethod.accuracyLabel)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.55))
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(result.floorAreaStr)
                        .font(.system(size: 36, weight: .bold, design: .default))
                        .foregroundColor(gold)
                    Text("m²")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(gold.opacity(0.7))
                }
            }
            .padding(24)

            Divider().background(Color.white.opacity(0.1))

            // Dimensions grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 0) {
                GuestDimCell(value: "\(result.lengthStr)m", label: "Length", gold: gold)
                GuestDimCell(value: "\(result.widthStr)m", label: "Width", gold: gold)
                GuestDimCell(value: "\(result.heightStr)m", label: "Height", gold: gold)
            }
            .padding(.vertical, 8)

            Divider().background(Color.white.opacity(0.1))

            // Room features row
            HStack(spacing: 0) {
                GuestFeatureCell(count: result.wallCount, label: "Walls", icon: "square.on.square")
                GuestFeatureCell(count: result.doorCount, label: "Doors", icon: "door.left.hand.open")
                GuestFeatureCell(count: result.windowCount, label: "Windows", icon: "window.casement")
            }
            .padding(.vertical, 4)

            Divider().background(Color.white.opacity(0.1))

            // Wall area
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total wall area")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.45))
                    Text(String(format: "%.1f m²", result.wallArea))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                }
                Spacer()
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(gold)
                    .font(.system(size: 20))
                Text("Scanned by AccuQuote")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(20)
        }
        .background(navy)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Dedicated share card (wider padding, branding for social)

struct GuestShareCard: View {
    let result: RoomDimensions
    let roomLabel: String
    let gold: Color
    let navy: Color

    var body: some View {
        ZStack {
            navy

            VStack(spacing: 24) {
                // Brand
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(gold)
                        .font(.system(size: 16))
                    Text("AccuQuote · Room Scanner")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                }

                // Big area number
                VStack(spacing: 4) {
                    Text(result.floorAreaStr)
                        .font(.system(size: 80, weight: .heavy, design: .default))
                        .foregroundColor(gold)
                    Text("square metres")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                    Text(roomLabel.isEmpty ? result.roomType : roomLabel)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                }

                // Dims strip
                HStack(spacing: 0) {
                    ShareDimPill(value: "\(result.lengthStr)m", label: "L")
                    Text("×")
                        .foregroundColor(.white.opacity(0.3))
                        .font(.system(size: 16))
                        .padding(.horizontal, 8)
                    ShareDimPill(value: "\(result.widthStr)m", label: "W")
                    Text("×")
                        .foregroundColor(.white.opacity(0.3))
                        .font(.system(size: 16))
                        .padding(.horizontal, 8)
                    ShareDimPill(value: "\(result.heightStr)m", label: "H")
                }

                // Method badge
                HStack(spacing: 6) {
                    Circle()
                        .fill(result.scanMethod == .lidar ? Color(hex: "#22C55E") : Color(hex: "#3B82F6"))
                        .frame(width: 7, height: 7)
                    Text(result.scanMethod.accuracyLabel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }

                // Footer
                Text("accuquote.app · Free room scanner")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.25))
            }
            .padding(40)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Upsell Banner

// Kept for backwards compatibility — no longer used in GuestResultView
struct GuestUpsellBanner: View {
    let gold: Color
    let navy: Color
    @Binding var showGuest: Bool

    var body: some View {
        GuestUpsellSheet(gold: gold, navy: navy, showGuest: $showGuest)
    }
}

struct GuestUpsellSheet: View {
    let gold: Color
    let navy: Color
    @Binding var showGuest: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Handle area spacing handled by presentationDragIndicator

            Text("ARE YOU A TRADESPERSON?")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(gold)
                .tracking(1.2)

            Text("This scan just became your quoting tool.")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(navy)

            Text("AccuQuote turns this room scan into a full itemised quote — with materials, live prices from your supplier, and a branded PDF. In minutes.")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .lineSpacing(4)

            VStack(spacing: 10) {
                Button {
                    dismiss()
                    showGuest = false
                } label: {
                    Text("Set up my trade profile")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(navy)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button { dismiss() } label: {
                    Text("Maybe later")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
            }
        }
        .padding(28)
        .padding(.top, 8)
    }
}

// MARK: - Guest Error

struct GuestErrorView: View {
    let message: String
    @ObservedObject var coordinator: ScanCoordinator

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            Text("Scan failed")
                .font(.title2.bold())
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try again") {
                coordinator.reset()
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 13)
            .background(Color(red: 0.06, green: 0.07, blue: 0.13))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Helper sub-views

struct GuestDimCell: View {
    let value: String
    let label: String
    let gold: Color

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }
}

struct GuestFeatureCell: View {
    let count: Int
    let label: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.4))
            Text("\(count)")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

struct ShareDimPill: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - iOS Share Sheet wrapper

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}

// MARK: - ScanState tag helper (for animation value)

extension ScanCoordinator {
    var stateTag: Int {
        switch state {
        case .ready:       return 0
        case .scanning:    return 1
        case .processing:  return 2
        case .complete:    return 3
        case .error:       return 4
        }
    }
}


