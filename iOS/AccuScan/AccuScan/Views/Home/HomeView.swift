import SwiftUI

// MARK: - Design Tokens

enum AS {
    // Palette
    static let bg         = Color(hex: "#07080A")
    static let surface1   = Color(hex: "#0C0E13")
    static let surface2   = Color(hex: "#111720")
    static let surface3   = Color(hex: "#1A2232")
    static let text       = Color(hex: "#EEE9DF")
    static let muted      = Color(hex: "#5A6A7E")
    static let lightBlue  = Color(hex: "#7DD3FC")  // accent — scan highlight
    static let green      = Color(hex: "#22C55E")
    static let blue       = Color(hex: "#3B82F6")
    static let teal       = Color(hex: "#14B8A6")
    static let amber      = Color(hex: "#FFD600")
    static let orange     = Color(hex: "#FF6B00")
}

// MARK: - HomeView

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var store = ScanStore.shared
    @State private var showDeleteConfirm: UUID?

    var body: some View {
        ZStack {
            AS.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Header ─────────────────────────────────────────────────
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ACCUSCAN")
                            .font(.system(size: 22, weight: .black, design: .default))
                            .tracking(4)
                            .foregroundColor(AS.lightBlue)
                        Text("Room Scanner")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AS.muted)
                    }
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 56)
                .padding(.bottom, 28)

                // ── New scan CTA ───────────────────────────────────────────
                Button {
                    appState.goSetup()
                } label: {
                    HStack(spacing: 12) {
                        // Fix #11 — official AR glyph (arkit SF symbol)
                        Image(systemName: "arkit")
                            .font(.system(size: 20, weight: .semibold))
                        Text("Scan a Room")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundColor(AS.bg)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(AS.lightBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .accessibilityLabel("Scan a new room")
                .padding(.horizontal, 24)
                .padding(.bottom, 32)

                // ── Scan history ───────────────────────────────────────────
                if store.scans.isEmpty {
                    EmptyScanStateView()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(store.scans) { meta in
                                ScanCardView(meta: meta) {
                                    // TODO: re-open saved scan (requires persisted USDZ)
                                } onDelete: {
                                    store.delete(meta.id)
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Empty state

struct EmptyScanStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.3.layers.3d")
                .font(.system(size: 48))
                .foregroundColor(AS.muted.opacity(0.4))
            Text("No scans yet")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(AS.text.opacity(0.6))
            // Fix #4 — no "LiDAR" tech term in user-facing copy
            Text("Tap Scan a Room to get started.\nWalls light up in real time as the room is measured.")
                .font(.system(size: 14))
                .foregroundColor(AS.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - Scan Card

struct ScanCardView: View {
    let meta: ScanMetadata
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Fix #12 — show real floor plan thumbnail when available
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AS.surface2)
                        .frame(width: 56, height: 56)
                    if let data = meta.thumbnailData, let img = UIImage(data: data) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        Image(systemName: meta.roomType.systemIcon)
                            .font(.system(size: 20))
                            .foregroundColor(AS.lightBlue)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(meta.name.isEmpty ? meta.roomType.rawValue : meta.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AS.text)
                    HStack(spacing: 8) {
                        Text(String(format: "%.1f m²", meta.floorArea))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AS.lightBlue)
                        Text("·")
                            .foregroundColor(AS.muted)
                        Text(meta.scanMethod.accuracyLabel)
                            .font(.system(size: 12))
                            .foregroundColor(AS.muted)
                    }
                    Text(meta.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 11))
                        .foregroundColor(AS.muted.opacity(0.6))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AS.muted.opacity(0.4))
            }
            .padding(16)
            .background(AS.surface1)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(AS.surface3, lineWidth: 1)
            )
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Color hex init (shared across the app)

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        let num = UInt64(h, radix: 16) ?? 0
        let r = Double((num >> 16) & 0xFF) / 255
        let g = Double((num >> 8)  & 0xFF) / 255
        let b = Double( num        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
