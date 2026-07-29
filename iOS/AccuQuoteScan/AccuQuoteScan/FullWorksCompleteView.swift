import SwiftUI
import RoomPlan

// MARK: - FullWorksCompleteView (Tri-Mode Scanning build spec §4.2)
//
// Completion screen: headline stat card (§4.2 "screenshot-bait by design")
// followed by the three deliverables — per-floor USDZ, per-floor 2D plans,
// dimension schedule CSV — each with its own share action, generated once
// on appear via FullWorksOutput.generate.

struct FullWorksCompleteView: View {
    @ObservedObject var session: FullWorksSession
    var onDone: () -> Void = {}

    @State private var isGenerating = true
    @State private var generationError: String?
    @State private var shareURL: URL?

    // Type-erased so this view compiles on the iOS 16 deployment target —
    // FullWorksOutput.Result itself is only @available(iOS 17, *); this
    // screen is only ever reached via FullWorksFlowView's own iOS 17 gate
    // (FullWorksSession.isSupported), so the erasure is just to satisfy the
    // compiler, not a real "might run on iOS 16" case.
    @State private var resultBox: Any?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                headerCard

                if isGenerating {
                    ProgressView("Preparing your export…")
                        .padding(.top, 40)
                } else if let generationError {
                    Text(generationError)
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                        .padding(.horizontal, 24)
                        .padding(.top, 24)
                } else if #available(iOS 17.0, *), let result = resultBox as? FullWorksOutput.Result {
                    deliverables(result)
                }

                Spacer(minLength: 40)

                Button(action: onDone) {
                    Text("Done")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AQ.blue)
                        .cornerRadius(14)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .background(AQ.fill)
        .onAppear { generate() }
        .sheet(item: $shareURL) { url in
            ShareSheet(url: url)
        }
    }

    // MARK: Header — completion stat card (§4.2 "screenshot-bait by design")

    private var headerCard: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                AQLogoView()
                Text(session.propertyName)
                    .font(.system(size: 12))
                    .foregroundColor(AQ.green)
            }
            .padding(.top, 40)

            Text("Scanned a \(session.totalRoomCount)-room property in \(session.scanDurationDescription ?? "no time")")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(AQ.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            HStack(spacing: 0) {
                StatCell(label: "Total area", value: "\(String(format: "%.1f", session.totalFloorAreaSqMetres)) m²")
                Divider().frame(height: 44).background(AQ.rule)
                StatCell(label: "Rooms", value: "\(session.totalRoomCount)")
                Divider().frame(height: 44).background(AQ.rule)
                StatCell(label: "Floors", value: "\(session.floors.count)")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Color.white)
    }

    // MARK: Deliverables

    @available(iOS 17.0, *)
    private func deliverables(_ result: FullWorksOutput.Result) -> some View {
        VStack(spacing: 12) {
            ForEach(session.floors) { floor in
                if let usdzURL = result.perFloorUSDZ[floor.id] {
                    deliverableRow(
                        icon: "cube.transparent",
                        title: "\(floor.label) — 3D model (USDZ)",
                        action: { shareURL = usdzURL }
                    )
                }
            }
            ForEach(session.floors) { floor in
                ForEach(floor.rooms) { record in
                    if let pdfURL = result.perFloorPlanPDF["\(floor.id)-\(record.id)"] {
                        deliverableRow(
                            icon: "doc.richtext",
                            title: "\(floor.label) — \(record.name) plan (PDF)",
                            action: { shareURL = pdfURL }
                        )
                    }
                }
            }
            if let csvURL = result.csvURL {
                deliverableRow(
                    icon: "tablecells",
                    title: "Dimension schedule (CSV)",
                    action: { shareURL = csvURL }
                )
            }
            if result.combinedUSDZ == nil {
                // Fix #10 — reworded from a limitation/apology ("isn't available
                // yet... share the per-floor models instead") to lead with what
                // the user can actually do, since each floor's model is a
                // genuinely complete, independently-shareable 3D file, not a
                // fallback for a missing feature. The RoomPlan API constraint
                // (no supported way to merge multiple CapturedStructures into
                // one scene) is real but belongs in a code comment, not the
                // user-facing caption.
                Text("Each floor's 3D model exports separately — open or share any floor above.")
                    .font(.system(size: 11))
                    .foregroundColor(AQ.secondary)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
    }

    private func deliverableRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AQ.blue)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AQ.ink)
                Spacer()
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 12))
                    .foregroundColor(AQ.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.white)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AQ.rule, lineWidth: 1))
        }
    }

    // MARK: Generation

    private func generate() {
        guard #available(iOS 17.0, *) else {
            generationError = "Full Works export requires iOS 17 or later."
            isGenerating = false
            return
        }
        let floors = session.floors
        let structures = session.mergedStructures
        do {
            let result = try FullWorksOutput.generate(floors: floors, mergedStructures: structures)
            resultBox = result
        } catch {
            generationError = "Couldn't prepare the export: \(error.localizedDescription)"
        }
        isGenerating = false
    }
}
