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
                            // #2 expand 44pt hit target around a visually small chevron
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(ScaleButtonStyle())   // #15
                    .accessibilityLabel("Back to home")
                    Spacer()
                    Text("New Scan")
                        .font(.subheadline.weight(.semibold))   // #1
                        .foregroundColor(AS.text)
                    Spacer()
                    Color.clear.frame(width: 44)   // balance the 44pt back button
                }
                .padding(.horizontal, 24)
                .padding(.top)   // #4 safe area
                .padding(.bottom, 28)

                ScrollView {
                    VStack(spacing: 28) {
                        // Device capability card
                        DeviceCapabilityCard(isLiDAR: isLiDAR)

                        // Room name
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Room name (optional)")
                                .font(.footnote.weight(.medium))   // #1
                                .foregroundColor(AS.muted)
                            TextField("e.g. Living Room, Master Bedroom…", text: $roomName)
                                .font(.body)   // #1
                                .foregroundColor(AS.text)
                                .focused($nameFieldFocused)
                                .submitLabel(.done)
                                .onChange(of: roomName) { v in
                                    if v.count > 64 { roomName = String(v.prefix(64)) }
                                }
                                .padding(16)
                                .background(AS.surface1)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.medium))   // #17
                                .overlay(
                                    RoundedRectangle(cornerRadius: Radius.medium)
                                        .stroke(nameFieldFocused ? AS.lightBlue : AS.surface3, lineWidth: 1)
                                )
                        }

                        // Room type picker
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Room type")
                                .font(.footnote.weight(.medium))   // #1
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
                        // #20: carry the user's room name + type into the scan
                        appState.pendingRoomName = roomName.trimmingCharacters(in: .whitespaces)
                        appState.pendingRoomType = roomType
                        appState.startScan()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "arkit")
                                .font(.system(size: 18, weight: .semibold))
                                .symbolRenderingMode(.hierarchical)   // #19
                                .accessibilityHidden(true)
                            Text("Scan this Room")
                                .font(.headline)   // #1
                        }
                        .foregroundColor(AS.bg)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(AS.lightBlue)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))   // #17
                    }
                    .buttonStyle(ScaleButtonStyle())   // #15
                    .accessibilityLabel("Start scanning this room")
                    .padding(.horizontal, 24)
                    .padding(.vertical, 24)
                } else {
                    VStack(spacing: 8) {
                        Text("Precision scanning requires an iPhone 12 Pro or later.")
                            .font(.subheadline.weight(.medium))   // #1
                            .foregroundColor(.orange)
                            .multilineTextAlignment(.center)
                        Text("Upgrade your device to use AccuScan.")
                            .font(.footnote)   // #1
                            .foregroundColor(AS.muted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity)
                    .background(Color.orange.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.large))   // #17
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
                Text(isLiDAR ? "Precision mode ready" : "Standard scanning")
                    .font(.subheadline.weight(.semibold))   // #1
                    .foregroundColor(AS.text)
                Text(isLiDAR ? "±1–2 cm accuracy · walls light up as they're measured"
                             : "This device doesn't support precision room scanning")
                    .font(.caption)   // #1
                    .foregroundColor(AS.muted)
                    .lineSpacing(3)
            }
        }
        .padding(16)
        .background(AS.surface1)
        .clipShape(RoundedRectangle(cornerRadius: Radius.large))   // #17
        .overlay(
            RoundedRectangle(cornerRadius: Radius.large)
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
                    .accessibilityHidden(true)
                Text(type.rawValue)
                    .font(.caption2.weight(.medium))   // #1
                    .foregroundColor(selected ? AS.bg : AS.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)   // #2 ensure 44pt touch target height
            .padding(.vertical, 12)
            .background(selected ? AS.lightBlue : AS.surface1)
            .clipShape(RoundedRectangle(cornerRadius: Radius.small))   // #17
            .overlay(
                RoundedRectangle(cornerRadius: Radius.small)
                    .stroke(selected ? AS.lightBlue : AS.surface3, lineWidth: 1)
            )
        }
        .buttonStyle(ScaleButtonStyle())   // #15
        // #27 Large Content Viewer so it stays usable at large accessibility text
        .accessibilityShowsLargeContentViewer {
            Label(type.rawValue, systemImage: type.systemIcon)
        }
        .accessibilityLabel("\(type.rawValue)\(selected ? ", selected" : "")")
    }
}
