import SwiftUI
import SceneKit
import ARKit
import simd

// MARK: - SpaceResultView (Tri-Mode Scanning build spec §3.2, §3.3, §6)
//
// Mirrors ResultView's card styling but for a SpaceDimensions void/frame
// measurement, plus §3.2's tap-to-measure: after capture the user taps any
// two points on the frozen 3D mesh and gets a point-to-point distance. Uses
// the shared ScanViewer3D (§6.1 "one component, all three modes") with its
// onMeasureTap hook, rather than a bespoke SceneKit view — Phase 5 replaced
// the original bespoke SpaceMeshMeasureView with this.

struct SpaceResultView: View {
    let dimensions: SpaceDimensions
    let coordinator: SpaceCaptureCoordinator
    var onDone: () -> Void = {}
    var onAttach: ((String) -> Void)?

    @State private var itemLabel = ""
    @State private var attached = false
    @State private var measurePoints: [SIMD3<Float>] = []
    @State private var lastMeasurement: Float?
    @StateObject private var exporter = SpaceExportState()

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    AQLogoView()
                    Text("Space measured")
                        .font(.system(size: 12))
                        .foregroundColor(AQ.green)
                }
                Spacer()
                ZStack {
                    Circle().fill(AQ.green.opacity(0.1)).frame(width: 36, height: 36)
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AQ.green)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 56)
            .padding(.bottom, 20)

            Divider().background(AQ.rule).padding(.horizontal, 24).padding(.bottom, 16)

            // Shared §6 viewer with tap-to-measure — the moment §3.2 calls
            // out as "the feature that makes a plumber measuring an
            // under-sink void gasp". Same orbit rig/control bar as Room mode
            // (§6.1 "one component, all three modes"), with onMeasureTap
            // wired instead of the rig's own gesture consuming single taps.
            ScanViewer3D(content: .spaceMesh(coordinator.frozenTriangles), onMeasureTap: { point in
                if measurePoints.count >= 2 { measurePoints = [] }
                measurePoints.append(point)
            })
                .frame(height: 320)
                .cornerRadius(16)
                .padding(.horizontal, 24)
                .onChange(of: measurePoints.count) { count in
                    guard count == 2 else { return }
                    lastMeasurement = coordinator.measureDistance(from: measurePoints[0], to: measurePoints[1])
                }

            if let measurement = lastMeasurement {
                HStack(spacing: 6) {
                    Image(systemName: "ruler")
                        .foregroundColor(AQ.blue)
                    Text("Tap distance: \(String(format: "%.0f", measurement * 1000))mm")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AQ.ink)
                    Spacer()
                    Button("Clear") { measurePoints = []; lastMeasurement = nil }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AQ.blue)
                }
                .padding(.horizontal, 24)
                .padding(.top, 10)
            } else {
                Text("Tap any two points on the mesh above to measure between them")
                    .font(.system(size: 12))
                    .foregroundColor(AQ.secondary)
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
            }

            // Dimensions card
            VStack(spacing: 0) {
                HStack {
                    Text("Void Dimensions")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AQ.secondary)
                        .kerning(0.8)
                        .textCase(.uppercase)
                    Spacer()
                    Text(dimensions.scanMethod.accuracyLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: dimensions.scanMethod.accuracyHex))
                }
                .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 20)

                Divider().background(AQ.rule).padding(.horizontal, 20)

                HStack(spacing: 0) {
                    DimensionCell(label: "Width",  value: dimensions.widthMM,  unit: "")
                    Divider().frame(height: 60).background(AQ.rule)
                    DimensionCell(label: "Height", value: dimensions.heightMM, unit: "")
                    Divider().frame(height: 60).background(AQ.rule)
                    DimensionCell(label: "Depth",  value: dimensions.depthMM,  unit: "")
                }
                .padding(.vertical, 4).padding(.bottom, 8)
            }
            .background(Color.white)
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AQ.rule, lineWidth: 1))
            .padding(.horizontal, 24)
            .padding(.top, 20)

            if let onAttach {
                SpaceAttachToQuoteCard(itemLabel: $itemLabel, attached: attached) {
                    onAttach(SpaceQuoteAttachment.note(itemLabel: itemLabel.isEmpty ? "Item" : itemLabel, dimensions: dimensions))
                    attached = true
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
            }

            SpaceExportButton(exporter: exporter, triangles: coordinator.frozenTriangles)
                .padding(.horizontal, 24)
                .padding(.top, 12)

            Spacer()

            VStack(spacing: 12) {
                Divider().background(AQ.rule)
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
                .padding(.bottom, 12)
            }
        }
        .background(Color.white)
    }
}

// MARK: - SpaceFrameResultView (§3.2 — window/door frame path)
//
// Same card layout as SpaceResultView, but for a FrameReveal: width/height/
// depth plus the two diagonals and a pass/fail square-check, which is the
// specific thing a fitter checks before ordering a replacement frame.

struct SpaceFrameResultView: View {
    let reveal: FrameReveal
    let coordinator: SpaceCaptureCoordinator
    var onDone: () -> Void = {}
    var onAttach: ((String) -> Void)?

    @State private var itemLabel = ""
    @State private var attached = false
    @State private var measurePoints: [SIMD3<Float>] = []
    @State private var lastMeasurement: Float?
    @StateObject private var exporter = SpaceExportState()

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    AQLogoView()
                    Text("Frame measured")
                        .font(.system(size: 12))
                        .foregroundColor(AQ.green)
                }
                Spacer()
                ZStack {
                    Circle().fill(AQ.green.opacity(0.1)).frame(width: 36, height: 36)
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AQ.green)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 56)
            .padding(.bottom, 20)

            Divider().background(AQ.rule).padding(.horizontal, 24).padding(.bottom, 16)

            ScanViewer3D(content: .spaceMesh(coordinator.frozenTriangles), onMeasureTap: { point in
                if measurePoints.count >= 2 { measurePoints = [] }
                measurePoints.append(point)
            })
                .frame(height: 320)
                .cornerRadius(16)
                .padding(.horizontal, 24)
                .onChange(of: measurePoints.count) { count in
                    guard count == 2 else { return }
                    lastMeasurement = coordinator.measureDistance(from: measurePoints[0], to: measurePoints[1])
                }

            if let measurement = lastMeasurement {
                HStack(spacing: 6) {
                    Image(systemName: "ruler")
                        .foregroundColor(AQ.blue)
                    Text("Tap distance: \(String(format: "%.0f", measurement * 1000))mm")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AQ.ink)
                    Spacer()
                    Button("Clear") { measurePoints = []; lastMeasurement = nil }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AQ.blue)
                }
                .padding(.horizontal, 24)
                .padding(.top, 10)
            } else {
                Text("Tap any two points on the mesh above to measure between them")
                    .font(.system(size: 12))
                    .foregroundColor(AQ.secondary)
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
            }

            VStack(spacing: 0) {
                HStack {
                    Text("Frame Reveal")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AQ.secondary)
                        .kerning(0.8)
                        .textCase(.uppercase)
                    Spacer()
                    Text(reveal.scanMethod.accuracyLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: reveal.scanMethod.accuracyHex))
                }
                .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 20)

                Divider().background(AQ.rule).padding(.horizontal, 20)

                HStack(spacing: 0) {
                    DimensionCell(label: "Width",  value: reveal.widthMM,  unit: "")
                    Divider().frame(height: 60).background(AQ.rule)
                    DimensionCell(label: "Height", value: reveal.heightMM, unit: "")
                    Divider().frame(height: 60).background(AQ.rule)
                    DimensionCell(label: "Depth",  value: reveal.depthMM,  unit: "")
                }
                .padding(.vertical, 4)

                Divider().background(AQ.rule).padding(.horizontal, 20)

                // Square-check — the diagonal comparison a fitter does before
                // ordering, surfaced automatically instead of left to the user
                // to notice on their own.
                HStack(spacing: 10) {
                    Image(systemName: reveal.isSquareWithinTolerance ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(reveal.isSquareWithinTolerance ? AQ.green : Color.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reveal.isSquareWithinTolerance ? "Square" : "Out of square")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AQ.ink)
                        Text("Diagonals: \(reveal.diagonalAMM) / \(reveal.diagonalBMM) (Δ\(String(format: "%.0f", reveal.diagonalDeltaMM))mm)")
                            .font(.system(size: 12))
                            .foregroundColor(AQ.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .background(Color.white)
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AQ.rule, lineWidth: 1))
            .padding(.horizontal, 24)
            .padding(.top, 20)

            if let onAttach {
                SpaceAttachToQuoteCard(itemLabel: $itemLabel, attached: attached) {
                    onAttach(SpaceQuoteAttachment.note(itemLabel: itemLabel.isEmpty ? "Item" : itemLabel, frame: reveal))
                    attached = true
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
            }

            SpaceExportButton(exporter: exporter, triangles: coordinator.frozenTriangles)
                .padding(.horizontal, 24)
                .padding(.top, 12)

            Spacer()

            VStack(spacing: 12) {
                Divider().background(AQ.rule)
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
                .padding(.bottom, 12)
            }
        }
        .background(Color.white)
    }
}

// MARK: - Attach to quote (§3.3 "a Space scan attaches to a quote section")

/// Lets the user label the item ("Replace kitchen sink unit") and attach the
/// measurement note to the in-progress job description, which flows into
/// both quote-section discovery and every section's generation prompt (see
/// QuoteGenerationService.generate's jobDescription parameter) — this is
/// what makes the AI actually see "void measured 562 × 448 × 585 mm" when it
/// prices the job.
struct SpaceAttachToQuoteCard: View {
    @Binding var itemLabel: String
    let attached: Bool
    let onAttach: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Attach to quote")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AQ.secondary)
                .kerning(0.8)
                .textCase(.uppercase)

            HStack(spacing: 10) {
                TextField("e.g. Replace kitchen sink unit", text: $itemLabel)
                    .font(.system(size: 14))
                    .foregroundColor(AQ.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).stroke(AQ.rule, lineWidth: 1))

                Button(action: onAttach) {
                    Text(attached ? "Attached" : "Attach")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(attached ? AQ.green : .white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .background(attached ? AQ.green.opacity(0.12) : AQ.blue)
                        .cornerRadius(10)
                }
            }
        }
    }
}

// MARK: - Export model (§3.3 "Textured mesh export... OBJ + USDZ")

@MainActor
final class SpaceExportState: ObservableObject {
    @Published var isExporting = false
    @Published var shareURL: URL?
    @Published var errorMessage: String?

    func export(triangles: [SpaceMeshExtraction.ExtractedTriangle]) {
        guard !isExporting else { return }
        isExporting = true
        errorMessage = nil
        let scanID = UUID().uuidString
        Task.detached(priority: .userInitiated) {
            do {
                let files = try SpaceMeshExport.export(triangles: triangles, scanID: scanID)
                await MainActor.run {
                    self.shareURL = files.usdzURL
                    self.isExporting = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Couldn't export the model. Try scanning again with more coverage."
                    self.isExporting = false
                }
            }
        }
    }
}

/// Distinct from the viewer's own Share button (which exports a transient
/// USDZ for AR Quick Look / one-off sharing): this persists both OBJ and
/// USDZ to Documents/aq_scans/ (§5.5), which is what a CAD/SketchUp workflow
/// or a "keep this scan around" use case needs — the file survives after the
/// share sheet closes, not just for the duration of one share action.
struct SpaceExportButton: View {
    @ObservedObject var exporter: SpaceExportState
    let triangles: [SpaceMeshExtraction.ExtractedTriangle]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                exporter.export(triangles: triangles)
            } label: {
                HStack(spacing: 8) {
                    if exporter.isExporting {
                        ProgressView().tint(AQ.blue)
                    } else {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 13, weight: .medium))
                    }
                    Text(exporter.isExporting ? "Saving model…" : "Save 3D model to Files (OBJ + USDZ)")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(AQ.blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(AQ.blue.opacity(0.08))
                .cornerRadius(12)
            }
            .disabled(exporter.isExporting || triangles.isEmpty)

            if let errorMessage = exporter.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
            }
        }
        .sheet(item: $exporter.shareURL) { url in
            ShareSheet(url: url)
        }
    }
}

