import SwiftUI
import RoomPlan
import simd

// MARK: - ScanReviewView
// Post-scan tabbed review: 3D model · Floor plan · Dimensions

struct ScanReviewView: View {
    @EnvironmentObject var appState: AppState
    let session: ScanSession

    enum Tab: String, CaseIterable {
        case model3D   = "3D"
        case floorPlan = "Floor Plan"
        case dimensions = "Dimensions"
    }

    @State private var activeTab: Tab = .model3D
    @State private var showUpsell = false

    var body: some View {
        ZStack {
            AS.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Nav
                HStack {
                    Button { appState.goHome() } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "house")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Home")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(AS.lightBlue)
                    }
                    Spacer()
                    Text(session.name.isEmpty ? session.roomType.rawValue : session.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AS.text)
                    Spacer()
                    Button { appState.showExport(session) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Export")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(AS.lightBlue)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 56)
                .padding(.bottom, 16)

                // Tab bar
                HStack(spacing: 0) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { activeTab = tab }
                            HapticService.shared.selection()
                        } label: {
                            Text(tab.rawValue)
                                .font(.system(size: 14, weight: activeTab == tab ? .semibold : .medium))
                                .foregroundColor(activeTab == tab ? AS.lightBlue : AS.muted)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .overlay(alignment: .bottom) {
                            if activeTab == tab {
                                Rectangle()
                                    .fill(AS.lightBlue)
                                    .frame(height: 2)
                            }
                        }
                    }
                }
                .background(AS.surface1)

                // Tab content
                switch activeTab {
                case .model3D:
                    ModelViewer3D(room: session.capturedRoom)
                case .floorPlan:
                    FloorPlanView(room: session.capturedRoom)
                case .dimensions:
                    DimensionTableView(session: session)
                }
            }
        }
        .sheet(isPresented: $showUpsell) {
            // Fix #5 — AccuQuoteUpsellSheet defined below; was previously a compile error
            AccuQuoteUpsellSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        // Fix #6 — use .task so the timer is cancelled if the user navigates away
        // before 2.5 s elapses. Also gate on a flag so it only shows once per install.
        .task {
            guard !UserDefaults.standard.bool(forKey: "hasSeenUpsell") else { return }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            showUpsell = true
            UserDefaults.standard.set(true, forKey: "hasSeenUpsell")
        }
    }
}

// MARK: - AccuQuoteUpsellSheet (Fix #5 — stub to resolve compile error)

struct AccuQuoteUpsellSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 4)
                .padding(.top, 12)

            Image(systemName: "bolt.fill")
                .font(.system(size: 40))
                .foregroundColor(AS.amber)

            Text("Upgrade to AccuQuote")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(AS.text)

            Text("Turn this room scan into an instant material quote and professional proposal — in under 2 minutes.")
                .font(.system(size: 15))
                .foregroundColor(AS.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button {
                dismiss()
            } label: {
                Text("Learn more")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AS.bg)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(AS.amber)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .background(AS.surface1.ignoresSafeArea())
    }
}

// MARK: - Dimension Table

struct DimensionTableView: View {
    let session: ScanSession
    // Fix #21 — computed property avoids storing a duplicate copy of session.capturedRoom
    private var room: CapturedRoom { session.capturedRoom }

    init(session: ScanSession) {
        self.session = session
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Summary cards
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    DimCard(value: String(format: "%.1f m²", session.floorArea),  label: "Floor Area",    color: AS.lightBlue)
                    DimCard(value: String(format: "%.1f m²", session.wallArea),   label: "Wall Area",     color: AS.teal)
                    DimCard(value: String(format: "%.2f m",  session.ceilingHeight), label: "Ceiling Height", color: AS.blue)
                    DimCard(value: "\(session.wallCount)",  label: "Walls",       color: AS.muted)
                }
                .padding(20)

                Divider().background(AS.surface3)

                // Wall details table
                VStack(alignment: .leading, spacing: 0) {
                    Text("WALLS")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AS.muted)
                        .tracking(1.5)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)

                    ForEach(Array(room.walls.enumerated()), id: \.offset) { i, wall in
                        WallRow(index: i + 1, wall: wall)
                        if i < room.walls.count - 1 {
                            Divider().background(AS.surface3).padding(.horizontal, 20)
                        }
                    }
                }

                if !room.doors.isEmpty {
                    Divider().background(AS.surface3)
                    SurfaceSection(title: "DOORS", items: room.doors.map { ($0.dimensions, $0.confidence) })
                }
                if !room.windows.isEmpty {
                    Divider().background(AS.surface3)
                    SurfaceSection(title: "WINDOWS", items: room.windows.map { ($0.dimensions, $0.confidence) })
                }

                Color.clear.frame(height: 40)
            }
        }
        .background(AS.bg)
    }
}

struct DimCard: View {
    let value: String; let label: String; let color: Color
    var body: some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AS.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(AS.surface1)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AS.surface3, lineWidth: 1))
    }
}

struct WallRow: View {
    let index: Int
    let wall: CapturedRoom.Wall

    var confidenceColor: Color {
        switch wall.confidence {
        case .high:   return AS.green
        case .medium: return AS.amber
        default:      return AS.muted
        }
    }

    var body: some View {
        HStack {
            Text("Wall \(index)")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AS.text)
            Spacer()
            HStack(spacing: 16) {
                DimPill(label: "W", value: String(format: "%.2fm", wall.dimensions.x))
                DimPill(label: "H", value: String(format: "%.2fm", wall.dimensions.y))
            }
            Circle()
                .fill(confidenceColor)
                .frame(width: 7, height: 7)
                .padding(.leading, 8)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

struct DimPill: View {
    let label: String; let value: String
    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(AS.muted)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(AS.text)
        }
    }
}

struct SurfaceSection: View {
    let title: String
    let items: [(simd_float3, CapturedRoom.Confidence)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(AS.muted)
                .tracking(1.5)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                HStack {
                    Text("\(title.capitalized.dropLast()) \(i + 1)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AS.text)
                    Spacer()
                    HStack(spacing: 16) {
                        DimPill(label: "W", value: String(format: "%.2fm", item.0.x))
                        DimPill(label: "H", value: String(format: "%.2fm", item.0.y))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                if i < items.count - 1 {
                    Divider().background(AS.surface3).padding(.horizontal, 20)
                }
            }
        }
    }
}
