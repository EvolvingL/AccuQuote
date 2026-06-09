import SwiftUI

// MARK: - Design Tokens

// Light palette — matched to AccuQuote's AQ tokens so the two apps share an
// identical look:
//   bg        = white page background
//   surface*  = AQ.fill / AQ.rule light greys
//   text      = AQ.ink near-black
//   muted     = AQ.secondary
//   lightBlue = the accent, now AQ.blue (iOS system blue), paired with white text
//   onAccent  = white text drawn on the accent fill (was AS.bg before the split)
//
// The live-scanning HUD overlays the camera feed with its own explicit
// dark/glass treatment, so it is unaffected by this light chrome.
enum AS {
    static let bg         = Color.white                               // page background
    static let surface1   = Color(red: 0.96, green: 0.96, blue: 0.97) // = AQ.fill
    static let surface2   = Color(red: 0.93, green: 0.93, blue: 0.95)
    static let surface3   = Color(red: 0.88, green: 0.88, blue: 0.91) // = AQ.rule
    static let text       = Color(red: 0.07, green: 0.07, blue: 0.09) // = AQ.ink
    static let muted      = Color(red: 0.52, green: 0.52, blue: 0.56) // = AQ.secondary
    static let lightBlue  = Color(red: 0.00, green: 0.48, blue: 1.00) // accent = AQ.blue
    static let onAccent   = Color.white                               // text on accent fill
    static let green      = Color(red: 0.13, green: 0.72, blue: 0.43) // = AQ.green
    static let blue       = Color(red: 0.00, green: 0.48, blue: 1.00)
    static let teal       = Color(hex: "#14B8A6")
    static let amber      = Color(red: 1.00, green: 0.80, blue: 0.00) // = AQ.amber
    static let orange     = Color(hex: "#FF6B00")
}

// MARK: - HomeView

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var store = ScanStore.shared
    @State private var showReopenNotice  = false
    @State private var pendingDeleteID:  UUID? = nil   // #5 confirmation dialog
    @State private var showDeleteConfirm = false

    var body: some View {
        ZStack {
            AS.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Header ─────────────────────────────────────────────────
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ACCUSCAN")
                            // #1 Dynamic Type: title text scales with user setting
                            .font(.title2.weight(.black))
                            .tracking(4)
                            .foregroundColor(AS.lightBlue)
                        Text("Room Scanner")
                            .font(.subheadline.weight(.medium))   // #1
                            .foregroundColor(AS.muted)
                    }
                    Spacer()
                }
                .padding(.horizontal, 24)
                // #4 safe area — use .padding(.top) and let SwiftUI read the inset
                .padding(.top)
                .padding(.bottom, 28)

                // ── New scan CTA ───────────────────────────────────────────
                Button { appState.goSetup() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "arkit")
                            .font(.system(size: 20, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)  // #19
                            .accessibilityHidden(true)           // #8 decorative inside button
                        Text("Scan a Room")
                            .font(.headline)                     // #1
                    }
                    .foregroundColor(AS.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(AS.lightBlue)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.xl))  // #17
                }
                .buttonStyle(ScaleButtonStyle())              // #15
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
                                    showReopenNotice = true
                                } onDelete: {
                                    // #5 require confirmation before irreversible delete
                                    pendingDeleteID  = meta.id
                                    showDeleteConfirm = true
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }

                Spacer(minLength: 0)
            }
        }
        // #5 Confirmation before destructive delete
        .confirmationDialog("Delete this scan?",
                            isPresented: $showDeleteConfirm,
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let id = pendingDeleteID { store.delete(id) }
                pendingDeleteID = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteID = nil }
        } message: {
            Text("This scan and its floor plan thumbnail will be permanently deleted.")
        }
        .alert("Scan Details", isPresented: $showReopenNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Re-opening saved scans is coming in a future update.")
        }
        // #6 Respond to system appearance — remove forced .dark override from AccuScanApp
    }
}

// MARK: - Empty state

struct EmptyScanStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.3.layers.3d")
                .font(.system(size: 48))
                .foregroundColor(AS.muted.opacity(0.4))
                .accessibilityHidden(true)   // #8 decorative
            Text("No scans yet")
                .font(.title3.weight(.semibold))   // #1
                .foregroundColor(AS.text.opacity(0.6))
            Text("Tap Scan a Room to get started.\nWalls light up in real time as the room is measured.")
                .font(.subheadline)   // #1
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
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.xs)   // #17
                        .fill(AS.surface2)
                        .frame(width: 56, height: 56)
                    if let data = ScanStore.shared.thumbnail(for: meta.id),
                       let img  = UIImage(data: data) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
                            .accessibilityLabel("\(meta.name.isEmpty ? meta.roomType.rawValue : meta.name) floor plan thumbnail")  // #8
                    } else {
                        Image(systemName: meta.roomType.systemIcon)
                            .font(.system(size: 20))
                            .foregroundColor(AS.lightBlue)
                            .accessibilityHidden(true)   // #8 decorative
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(meta.name.isEmpty ? meta.roomType.rawValue : meta.name)
                        .font(.subheadline.weight(.semibold))   // #1
                        .foregroundColor(AS.text)
                    HStack(spacing: 8) {
                        Text(String(format: "%.1f m²", meta.floorArea))
                            .font(.footnote.weight(.medium))   // #1
                            .foregroundColor(AS.lightBlue)
                        Text("·").foregroundColor(AS.muted)
                        Text(meta.scanMethod.accuracyLabel)
                            .font(.caption)   // #1
                            .foregroundColor(AS.muted)
                    }
                    Text(meta.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)   // #1
                        .foregroundColor(AS.muted.opacity(0.6))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AS.muted.opacity(0.4))
                    .accessibilityHidden(true)   // #8 decorative
            }
            .padding(16)
            .background(AS.surface1)
            .clipShape(RoundedRectangle(cornerRadius: Radius.large))   // #17
            .overlay(RoundedRectangle(cornerRadius: Radius.large).stroke(AS.surface3, lineWidth: 1))
        }
        .buttonStyle(ScaleButtonStyle())   // #15
        // #29 Context menu for long-press quick actions
        .contextMenu {
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete Scan", systemImage: "trash")
            }
        }
        // #5 Swipe-to-delete triggers confirmation (via parent)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Color hex init

extension Color {
    init(hex: String) {
        let h   = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        let num = UInt64(h, radix: 16) ?? 0
        let r   = Double((num >> 16) & 0xFF) / 255
        let g   = Double((num >> 8)  & 0xFF) / 255
        let b   = Double( num        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
