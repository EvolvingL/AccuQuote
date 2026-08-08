#if DEBUG
import SwiftUI

// MARK: - DevToolsView
//
// A single, growing checklist for manually verifying each phase of the
// Tri-Mode Scanning build (see Accu-TriModeScanning-BuildSpec.md) as it
// lands, without waiting until every phase is done to test anything.
// Each row runs one isolated piece of new functionality and reports
// pass/fail + a short result string inline — no need to complete a real
// scan or navigate the full app to exercise model/logic code.
//
// Entirely compiled out of Release/App Store builds via #if DEBUG at the
// top of this file, matching the existing debug-entitlement-bypass
// convention in AuthViews.swift.
//
// Add one row per testable unit as each build-plan phase lands. Remove a
// row once its functionality is fully exercised through the real UI and a
// manual check is no longer useful (e.g. once the mode picker and live
// Space-mode capture exist, the "construct a fixture ScanResult" row below
// can go — the real flow tests it better than a synthetic fixture would).

struct DevToolsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var results: [String: DevCheckResult] = [:]
    @State private var showSpaceScan = false
    @State private var showFloorPlanPreview = false
    @State private var showFullWorks = false

    private var checks: [DevCheck] {
        [
            // Phase 0 — shared models
            DevCheck(id: "phase0.codable", label: "Phase 0: ScanResult encodes/decodes round-trip") {
                DevToolsChecks.scanResultRoundTrip()
            },
            DevCheck(id: "phase0.backcompat", label: "Phase 0: old-shape JSON decodes with safe defaults") {
                DevToolsChecks.scanResultBackwardsCompatibleDecode()
            },

            // Phase 1 — quality gate (rows added as heuristics land)
            DevCheck(id: "phase1.gate.pass", label: "Phase 1: gate passes a clean fixture room") {
                DevToolsChecks.qualityGatePassesCleanRoom()
            },
            DevCheck(id: "phase1.gate.openloop", label: "Phase 1: gate flags an open-loop wall as blocking") {
                DevToolsChecks.qualityGateFlagsOpenLoop()
            },
            DevCheck(id: "phase1.patch.prefersPassing", label: "Phase 1: patch resolution prefers a passing result") {
                DevToolsChecks.patchResolutionPrefersPassingResult()
            },
            DevCheck(id: "phase1.patch.noDataLoss", label: "Phase 1: patch resolution protects against data loss") {
                DevToolsChecks.patchResolutionProtectsAgainstDataLoss()
            },

            // Phase 4 — Space mode (capture-volume + on-device tests only;
            // no LiDAR/real scan test here — see the manual on-device
            // checklist in the build plan for coverage-ring/completion tests)
            DevCheck(id: "phase4.obb.axisAligned", label: "Phase 4: OBB fits an axis-aligned box correctly") {
                DevToolsChecks.obbFitsAxisAlignedBox()
            },
            DevCheck(id: "phase4.obb.rotated", label: "Phase 4: OBB fits a rotated box correctly") {
                DevToolsChecks.obbFitsRotatedBox()
            },
            DevCheck(id: "phase4.captureVolume.contains", label: "Phase 4: capture volume containment respects rotation") {
                DevToolsChecks.captureVolumeContainmentRespectsRotation()
            },
            DevCheck(id: "phase4.tapToMeasure", label: "Phase 4: tap-to-measure distance is accurate") {
                DevToolsChecks.tapToMeasureDistance()
            },
            DevCheck(id: "phase4.frame.square", label: "Phase 4: frame fitting measures a square frame correctly") {
                DevToolsChecks.frameRectangleFitsSquareFrame()
            },
            DevCheck(id: "phase4.frame.racked", label: "Phase 4: frame fitting flags a racked (out-of-square) frame") {
                DevToolsChecks.frameRectangleFlagsRackedFrame()
            },
            DevCheck(id: "phase4.quoteAttachment.copy", label: "Phase 4: quote-attachment copy matches spec format") {
                DevToolsChecks.quoteAttachmentCopyMatchesSpecFormat()
            },

            // Phase 5 — shared 3D viewer (§6). Camera rig/gesture behaviour
            // needs a real device to check by hand (see the on-device UAT
            // checklist); this covers the one piece of pure math involved.
            DevCheck(id: "phase5.viewer.labelFade", label: "Phase 5: dimension labels fade at the correct zoom distance") {
                DevToolsChecks.dimensionLabelsFadeAtCorrectDistance()
            },

            // Phase 6 — Full Works / floor plan renderer (§4, §5.2). Actual
            // Canvas drawing needs eyeballing (see "Preview floor plan
            // renderer" button below); this covers the projection math.
            DevCheck(id: "phase6.floorplan.rectangularRoom", label: "Phase 6: floor plan builder projects a rectangular room correctly") {
                DevToolsChecks.floorPlanBuilderProjectsRectangularRoom()
            },
            DevCheck(id: "phase6.floorplan.nearestWall", label: "Phase 6: openings associate with the nearest wall") {
                DevToolsChecks.floorPlanBuilderAssociatesOpeningsToNearestWall()
            },
            DevCheck(id: "phase6.floorplan.overallDims", label: "Phase 6: overall bounding dimensions match the room's bounding box") {
                DevToolsChecks.floorPlanOverallDimensionsMatchBoundingBox()
            },
            DevCheck(id: "phase6.csv.escaping", label: "Phase 6: dimension schedule CSV escapes commas/quotes") {
                DevToolsChecks.fullWorksCSVEscapesSpecialCharacters()
            },
            DevCheck(id: "phase6.csv.roundTrip", label: "Phase 6: dimension schedule CSV round-trips correctly") {
                DevToolsChecks.fullWorksCSVRoundTripsDimensionSchedule()
            },

            // Phase 7 — mode picker, persistence & history (§1, §7)
            DevCheck(id: "phase7.savedQuote.backcompat", label: "Phase 7: old-shape SavedQuote JSON decodes with safe defaults") {
                DevToolsChecks.savedQuoteDecodesOldJSONWithSafeDefaults()
            },
            DevCheck(id: "phase7.savedQuote.thumbnailURL", label: "Phase 7: thumbnailURL derives correctly from scanArtifactURL") {
                DevToolsChecks.savedQuoteThumbnailURLDerivesFromArtifactURL()
            },
            DevCheck(id: "phase7.storage.retentionWindow", label: "Phase 7: storage cleanup respects the 90-day retention window") {
                DevToolsChecks.scanStorageCleanupRespectsRetentionWindow()
            },
        ]
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(checks) { check in
                        DevCheckRow(check: check, result: results[check.id]) {
                            results[check.id] = check.run()
                        }
                    }
                } header: {
                    Text("Tri-Mode Scanning — build checkpoints")
                } footer: {
                    Text("Debug-only. Tap a row to run it. This screen and every row in it is removed as each phase becomes verifiable through the real app UI.")
                }

                Section {
                    Button("Run all") {
                        for check in checks { results[check.id] = check.run() }
                    }
                }

                Section {
                    Button("Try Space mode (live capture)") { showSpaceScan = true }
                } footer: {
                    Text("Launches the real ARKit capture flow — needs a LiDAR device to place a capture volume; falls back to manual entry otherwise. Not gated by the mode picker yet (Phase 7).")
                }

                Section {
                    Button("Preview floor plan renderer (fixture room)") { showFloorPlanPreview = true }
                } footer: {
                    Text("Renders a synthetic 4-wall room fixture through FloorPlan2DRenderer — CapturedRoom has no public initializer, so this is the only way to eyeball the renderer without a real LiDAR scan.")
                }

                Section {
                    Button("Try Full Works (live multi-room capture)") { showFullWorks = true }
                } footer: {
                    Text("Launches the real multi-room capture + StructureBuilder merge flow — needs a LiDAR device and iOS 17+. Not gated by the mode picker yet (Phase 7); no paywall (§4.3 — included in all AccuQuoteScan tiers).")
                }
            }
            .navigationTitle("Dev Tools")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showSpaceScan) {
                SpaceScanFlowView(onDone: { showSpaceScan = false })
            }
            .fullScreenCover(isPresented: $showFloorPlanPreview) {
                NavigationStack {
                    FloorPlan2DView(plan: DevToolsChecks.fixtureFloorPlan())
                        .navigationTitle("Floor Plan Preview")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") { showFloorPlanPreview = false }
                            }
                        }
                }
            }
            .fullScreenCover(isPresented: $showFullWorks) {
                FullWorksFlowView(onDone: { showFullWorks = false })
            }
        }
    }
}

private struct DevCheck: Identifiable {
    let id: String
    let label: String
    let run: () -> DevCheckResult
}

struct DevCheckResult {
    let passed: Bool
    let detail: String
}

private struct DevCheckRow: View {
    let check: DevCheck
    let result: DevCheckResult?
    let onRun: () -> Void

    var body: some View {
        Button(action: onRun) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: iconName)
                    .foregroundColor(iconColor)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(check.label)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                    if let result {
                        Text(result.detail)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private var iconName: String {
        guard let result else { return "circle" }
        return result.passed ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    private var iconColor: Color {
        guard let result else { return .secondary }
        return result.passed ? .green : .red
    }
}
#endif
