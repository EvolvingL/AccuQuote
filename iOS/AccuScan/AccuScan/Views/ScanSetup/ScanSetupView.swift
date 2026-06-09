import SwiftUI

// MARK: - ScanSetupView
// Room name + type picker before scanning begins.
// Shows LiDAR vs camera-sweep device capability.

struct ScanSetupView: View {
    @EnvironmentObject var appState: AppState
    @State private var roomName: String = ""
    @State private var roomType: RoomType = .livingRoom
    @FocusState private var nameFieldFocused: Bool

    var isLiDAR: Bool { ScanSessionManager.supportsLiDAR }

    var body: some View {
        ZStack {
            AS.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Nav
                HStack {
                    Button { appState.goHome() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AS.text.opacity(0.6))
                    }
                    Spacer()
                    Text("New Scan")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AS.text)
                    Spacer()
                    // Balance spacer
                    Color.clear.frame(width: 24)
                }
                .padding(.horizontal, 24)
                .padding(.top, 56)
                .padding(.bottom, 28)

                ScrollView {
                    VStack(spacing: 28) {
                        // Device capability card
                        DeviceCapabilityCard(isLiDAR: isLiDAR)

                        // Room name
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Room name (optional)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AS.muted)
                            TextField("e.g. Living Room, Master Bedroom…", text: $roomName)
                                .font(.system(size: 16))
                                .foregroundColor(AS.text)
                                .focused($nameFieldFocused)
                                // Fix #21: cap room name at 64 chars — prevents excessively
                                // long names becoming problematic export filenames
                                .onChange(of: roomName) { v in
                                    if v.count > 64 { roomName = String(v.prefix(64)) }
                                }
                                .padding(16)
                                .background(AS.surface1)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(nameFieldFocused ? AS.lightBlue : AS.surface3, lineWidth: 1)
                                )
                        }

                        // Room type picker
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Room type")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AS.muted)
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                ForEach(RoomType.allCases, id: \.self) { type in
                                    RoomTypePill(type: type, selected: roomType == type) {
                                        roomType = type
                                        HapticService.shared.selection()
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                }

                // Fix #2: gate to LiDAR-capable devices; show friendly message otherwise
                if isLiDAR {
                    Button {
                        nameFieldFocused = false
                        appState.startScan()
                    } label: {
                        HStack(spacing: 10) {
                            // Fix #11 — official AR entry-point glyph
                            Image(systemName: "arkit")
                                .font(.system(size: 18, weight: .semibold))
                            // Fix #4 — plain language, no "LiDAR" tech term
                            Text("Scan this Room")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundColor(AS.bg)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(AS.lightBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .accessibilityLabel("Start scanning this room")
                    .padding(.horizontal, 24)
                    .padding(.vertical, 24)
                } else {
                    // Fix #2 — graceful non-LiDAR message, no crash path
                    VStack(spacing: 8) {
                        Text("Precision scanning requires an iPhone 12 Pro or later.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.orange)
                            .multilineTextAlignment(.center)
                        Text("Upgrade your device to use AccuScan.")
                            .font(.system(size: 13))
                            .foregroundColor(AS.muted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity)
                    .background(Color.orange.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 24)
                }
            }
        }
    }
}

// MARK: - Device capability card

struct DeviceCapabilityCard: View {
    let isLiDAR: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill((isLiDAR ? AS.green : AS.blue).opacity(0.12))
                    .frame(width: 48, height: 48)
                // Fix #15 — consistent arkit glyph for LiDAR capability card
                Image(systemName: isLiDAR ? "arkit" : "camera.viewfinder")
                    .font(.system(size: 20))
                    .foregroundColor(isLiDAR ? AS.green : AS.blue)
            }
            VStack(alignment: .leading, spacing: 4) {
                // Fix #4 — friendly terms, no "LiDAR" exposed to end users
                Text(isLiDAR ? "Precision mode ready" : "Standard scanning")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AS.text)
                Text(isLiDAR ? "±1–2 cm accuracy · walls light up as they're measured"
                             : "This device doesn't support precision room scanning")
                    .font(.system(size: 12))
                    .foregroundColor(AS.muted)
                    .lineSpacing(3)
            }
        }
        .padding(16)
        .background(AS.surface1)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke((isLiDAR ? AS.green : AS.blue).opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - Room type pill

struct RoomTypePill: View {
    let type: RoomType
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Image(systemName: type.systemIcon)
                    .font(.system(size: 18))
                    .foregroundColor(selected ? AS.bg : AS.muted)
                Text(type.rawValue)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(selected ? AS.bg : AS.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(selected ? AS.lightBlue : AS.surface1)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selected ? AS.lightBlue : AS.surface3, lineWidth: 1)
            )
        }
    }
}
