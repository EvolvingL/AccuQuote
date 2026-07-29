#if DEBUG
import Foundation
import simd

// MARK: - DevToolsChecks
//
// The actual assertions behind each DevToolsView row. Kept separate from the
// view so the checks themselves stay simple, synchronous functions — no
// SwiftUI, no @MainActor requirement, easy to read top to bottom against
// the build-plan phase they verify.

enum DevToolsChecks {

    // MARK: Phase 0 — shared models

    static func scanResultRoundTrip() -> DevCheckResult {
        let original = ScanResult(
            mode: .room,
            surfaces: [Surface(category: .wall, polygon: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(1, 0, 1)], confidence: 0.9)],
            dimensionSchedule: [RoomDimensionRecord(roomName: "Kitchen", length: 4.2, width: 3.1, height: 2.4,
                                                     floorArea: 13.02, wallArea: 35.04, doorCount: 1, windowCount: 2)]
        )
        do {
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(ScanResult.self, from: data)
            let ok = decoded.id == original.id
                && decoded.mode == original.mode
                && decoded.surfaces.count == 1
                && decoded.dimensionSchedule.first?.roomName == "Kitchen"
            return DevCheckResult(passed: ok, detail: ok ? "Round-trip OK — \(data.count) bytes" : "Decoded value didn't match original")
        } catch {
            return DevCheckResult(passed: false, detail: "Encode/decode threw: \(error)")
        }
    }

    static func scanResultBackwardsCompatibleDecode() -> DevCheckResult {
        // Simulates a ScanResult saved by an older build, before confidence/
        // floorPlan2D/dimensionSchedule existed — only the fields present at
        // Room-mode launch. Decoding this must not throw, and must fall back
        // to the safe defaults each type's custom init(from:) declares.
        let oldShapeJSON = """
        {"id":"abc-123","mode":"room","capturedAt":\(Date().timeIntervalSinceReferenceDate)}
        """.data(using: .utf8)!

        do {
            let decoded = try JSONDecoder().decode(ScanResult.self, from: oldShapeJSON)
            let ok = decoded.surfaces.isEmpty
                && decoded.dimensionSchedule.isEmpty
                && decoded.confidence.overallScore == 1.0
                && decoded.confidence.isPassing
                && decoded.floorPlan2D.walls.isEmpty
            return DevCheckResult(passed: ok, detail: ok ? "Old-shape JSON decoded with safe defaults" : "Defaults didn't match expectations")
        } catch {
            return DevCheckResult(passed: false, detail: "Threw on old-shape JSON: \(error)")
        }
    }

    // MARK: Phase 1 — quality gate
    //
    // Exercises ScanQualityGate's pure evaluate(walls:...) overload with
    // literal WallSample fixtures — CapturedRoom itself has no public
    // initializer (decode-only, framework-constructed), so the
    // CapturedRoom-taking overload can only be verified by a real scan.
    // See ScanQualityGate.swift's header comment for the two-layer design.

    static func qualityGatePassesCleanRoom() -> DevCheckResult {
        let walls = (0..<4).map { i in
            WallSample(id: "wall-\(i)", lengthMetres: 3.5, leftEdgeClosed: true, rightEdgeClosed: true, confidence: .high)
        }
        let confidence = ScanQualityGate.evaluate(walls: walls)
        let ok = confidence.isPassing && confidence.issues.isEmpty && confidence.overallScore == 1.0
        return DevCheckResult(
            passed: ok,
            detail: ok ? "4 clean walls → isPassing, score 1.0" : "score=\(confidence.overallScore) issues=\(confidence.issues.count)"
        )
    }

    static func qualityGateFlagsOpenLoop() -> DevCheckResult {
        var walls = (0..<4).map { i in
            WallSample(id: "wall-\(i)", lengthMetres: 3.5, leftEdgeClosed: true, rightEdgeClosed: true, confidence: .high)
        }
        // Simulate "the room that doesn't close": one wall's right edge
        // never got confirmed against its neighbour.
        walls[2] = WallSample(id: "wall-2", lengthMetres: 3.5, leftEdgeClosed: true, rightEdgeClosed: false, confidence: .high)

        let confidence = ScanQualityGate.evaluate(walls: walls)
        let openLoop = confidence.issues.first { $0.kind == .openLoop }
        let ok = !confidence.isPassing
            && openLoop != nil
            && openLoop?.severity == .blocking
            && openLoop?.affectedSurfaceIDs == ["wall-2"]
        return DevCheckResult(
            passed: ok,
            detail: ok ? "Open-loop wall correctly flagged blocking, gate fails" : "Expected a blocking openLoop issue on wall-2, got: \(confidence.issues)"
        )
    }

    // MARK: Phase 1 — patch-mode resolution

    static func patchResolutionPrefersPassingResult() -> DevCheckResult {
        // A passing new result should always beat a failing prior result,
        // even if the prior has more walls — this is the "don't silently
        // discard a scan that actually fixed the problem" case.
        let preferNew = ScanCoordinator.shouldPreferNew(
            priorIsPassing: false, priorWallCount: 6, priorScore: 0.5,
            newIsPassing: true, newWallCount: 4, newScore: 1.0
        )
        return DevCheckResult(
            passed: preferNew,
            detail: preferNew ? "Passing 4-wall result correctly preferred over failing 6-wall result" : "Expected new (passing) result to win"
        )
    }

    static func patchResolutionProtectsAgainstDataLoss() -> DevCheckResult {
        // If the resumed RoomCaptureSession doesn't behave as hoped (this
        // codebase has never previously exercised re-running an existing
        // session — see startPatchScan's doc comment), a fresh capture of
        // just the patched corner would have fewer walls than the original
        // full room. Both pass the gate here — the prior, larger, still-
        // passing result must win, not be silently discarded.
        let preferNew = ScanCoordinator.shouldPreferNew(
            priorIsPassing: true, priorWallCount: 6, priorScore: 0.9,
            newIsPassing: true, newWallCount: 2, newScore: 1.0
        )
        return DevCheckResult(
            passed: !preferNew,
            detail: !preferNew ? "Smaller non-cumulative new capture correctly rejected in favour of the fuller prior result" : "Expected prior (more complete) result to win"
        )
    }

    // MARK: Phase 4 — Space mode
    //
    // Exercises SpaceMeasurement's pure functions with literal SIMD3<Float>
    // fixtures. SpaceMeshExtraction (the ARMeshAnchor-reading layer) can't be
    // fixture-tested the same way ScanQualityGate's CapturedRoom extraction
    // can't — ARMeshAnchor is a real-scan-only, framework-constructed type —
    // so these checks only cover the math that runs after extraction.

    static func obbFitsAxisAlignedBox() -> DevCheckResult {
        // 8 corners of a 2×1×0.5m box centred at the origin, axis-aligned —
        // the simplest possible case: PCA on an axis-aligned box's corners
        // should recover axes matching world X/Y/Z (in some order/sign) and
        // extents matching the box dimensions exactly.
        let points: [SIMD3<Float>] = [
            SIMD3(-1, -0.5, -0.25), SIMD3(1, -0.5, -0.25), SIMD3(-1, 0.5, -0.25), SIMD3(1, 0.5, -0.25),
            SIMD3(-1, -0.5,  0.25), SIMD3(1, -0.5,  0.25), SIMD3(-1, 0.5,  0.25), SIMD3(1, 0.5,  0.25),
        ]
        guard let obb = SpaceMeasurement.orientedBoundingBox(of: points) else {
            return DevCheckResult(passed: false, detail: "orientedBoundingBox returned nil")
        }
        let dims = SpaceDimensions(obb: obb)
        // Sorted-descending per SpaceDimensions(obb:)'s own convention: 2.0, 1.0, 0.5
        let ok = abs(dims.width - 2.0) < 0.02 && abs(dims.height - 1.0) < 0.02 && abs(dims.depth - 0.5) < 0.02
            && simd_length(obb.center) < 0.02
        return DevCheckResult(
            passed: ok,
            detail: ok ? "Axis-aligned box → \(dims.widthStr)×\(dims.heightStr)×\(dims.depthStr)m, centred at origin"
                       : "Got \(dims.widthStr)×\(dims.heightStr)×\(dims.depthStr)m, centre \(obb.center) — expected ~2.0×1.0×0.5m at origin"
        )
    }

    static func obbFitsRotatedBox() -> DevCheckResult {
        // Same 2×1×0.5m box, rotated 30° about Y and offset from the origin —
        // confirms PCA recovers the box's actual size regardless of world
        // orientation/position, not just the trivial axis-aligned case.
        let angle: Float = 30 * .pi / 180
        let rotation = simd_quatf(angle: angle, axis: SIMD3<Float>(0, 1, 0))
        let offset = SIMD3<Float>(3, 1, -2)
        let localCorners: [SIMD3<Float>] = [
            SIMD3(-1, -0.5, -0.25), SIMD3(1, -0.5, -0.25), SIMD3(-1, 0.5, -0.25), SIMD3(1, 0.5, -0.25),
            SIMD3(-1, -0.5,  0.25), SIMD3(1, -0.5,  0.25), SIMD3(-1, 0.5,  0.25), SIMD3(1, 0.5,  0.25),
        ]
        let worldPoints = localCorners.map { rotation.act($0) + offset }

        guard let obb = SpaceMeasurement.orientedBoundingBox(of: worldPoints) else {
            return DevCheckResult(passed: false, detail: "orientedBoundingBox returned nil")
        }
        let dims = SpaceDimensions(obb: obb)
        let ok = abs(dims.width - 2.0) < 0.02 && abs(dims.height - 1.0) < 0.02 && abs(dims.depth - 0.5) < 0.02
            && simd_distance(obb.center, offset) < 0.02
        return DevCheckResult(
            passed: ok,
            detail: ok ? "Rotated+offset box → \(dims.widthStr)×\(dims.heightStr)×\(dims.depthStr)m, centre within 2cm of expected"
                       : "Got \(dims.widthStr)×\(dims.heightStr)×\(dims.depthStr)m, centre \(obb.center) — expected ~2.0×1.0×0.5m near \(offset)"
        )
    }

    static func captureVolumeContainmentRespectsRotation() -> DevCheckResult {
        // A capture volume rotated 45° about Y: a point that's inside the
        // box's local frame but would be OUTSIDE an axis-aligned box at the
        // same world position must still be correctly classified as inside —
        // this is what confirms the containment check actually rotates the
        // test point into the box's local frame rather than treating
        // orientation as a no-op.
        let rotation = simd_quatf(angle: .pi / 4, axis: SIMD3<Float>(0, 1, 0))
        let volume = CaptureVolume(center: .zero, size: SIMD3<Float>(1, 1, 1), orientation: rotation)

        // This point sits well outside an axis-aligned 1×1×1 box at the
        // origin (its raw X is 0.9), but after undoing the 45° rotation it
        // lands near the box's local +Z face, inside the ±0.5 half-extent.
        let pointInsideWhenRotated = rotation.act(SIMD3<Float>(0, 0, 0.4))
        let pointOutsideRegardless = SIMD3<Float>(5, 5, 5)

        let insideOk = volume.contains(worldPoint: pointInsideWhenRotated)
        let outsideOk = !volume.contains(worldPoint: pointOutsideRegardless)
        let ok = insideOk && outsideOk
        return DevCheckResult(
            passed: ok,
            detail: ok ? "Rotated capture volume correctly classifies inside/outside points"
                       : "insideOk=\(insideOk) outsideOk=\(outsideOk) — rotation not applied correctly to containment check"
        )
    }

    static func tapToMeasureDistance() -> DevCheckResult {
        // Simple 3-4-5 right triangle in 3D — exact, easy-to-verify-by-hand distance.
        let a = SIMD3<Float>(0, 0, 0)
        let b = SIMD3<Float>(3, 4, 0)
        let distance = SpaceMeasurement.pointToPointDistance(a, b)
        let ok = abs(distance - 5.0) < 0.001
        return DevCheckResult(
            passed: ok,
            detail: ok ? "3-4-5 triangle → \(String(format: "%.3f", distance))m (±1cm target easily met)"
                       : "Got \(distance)m, expected 5.0m"
        )
    }

    static func frameRectangleFitsSquareFrame() -> DevCheckResult {
        // A perfectly flat, square 0.6 × 0.6m frame face in the XY plane
        // (constant Z) — the trivial case: the fitted rectangle's width/
        // height should match exactly and the two real diagonals (measured
        // from the same 4 corner points) should be equal, since a perfect
        // square can't be racked.
        let points: [SIMD3<Float>] = [
            SIMD3(-0.3, -0.3, 1.0), SIMD3(0.3, -0.3, 1.0),
            SIMD3(-0.3,  0.3, 1.0), SIMD3(0.3,  0.3, 1.0),
        ]
        guard let rect = SpaceMeasurement.fittedRectangle(of: points) else {
            return DevCheckResult(passed: false, detail: "fittedRectangle returned nil")
        }
        let corners = SpaceMeasurement.actualCorners(of: points, nearestTo: rect)
        let reveal = FrameReveal(rectangle: rect, corners: corners, depth: 0.1, scanMethod: .lidar)
        let ok = abs(reveal.width - 0.6) < 0.02 && abs(reveal.height - 0.6) < 0.02 && reveal.isSquareWithinTolerance
        return DevCheckResult(
            passed: ok,
            detail: ok ? "Square frame → \(reveal.widthMM)×\(reveal.heightMM), diagonals match (square)"
                       : "Got \(reveal.widthMM)×\(reveal.heightMM), Δdiagonal=\(reveal.diagonalDeltaMM)mm — expected ~600×600mm, square"
        )
    }

    static func frameRectangleFlagsRackedFrame() -> DevCheckResult {
        // Same 0.6×0.6m nominal frame, but one corner pulled 20mm out of
        // plane-aligned position — simulates a racked (out-of-square) real
        // frame. The two actual diagonals should now differ meaningfully,
        // which is exactly what a fitter needs surfaced before ordering.
        let points: [SIMD3<Float>] = [
            SIMD3(-0.3, -0.3, 1.0), SIMD3(0.3, -0.3, 1.0),
            SIMD3(-0.3,  0.3, 1.0), SIMD3(0.32, 0.32, 1.0),   // racked corner
        ]
        guard let rect = SpaceMeasurement.fittedRectangle(of: points) else {
            return DevCheckResult(passed: false, detail: "fittedRectangle returned nil")
        }
        let corners = SpaceMeasurement.actualCorners(of: points, nearestTo: rect)
        let reveal = FrameReveal(rectangle: rect, corners: corners, depth: 0.1, scanMethod: .lidar)
        let ok = !reveal.isSquareWithinTolerance && reveal.diagonalDeltaMM > 5.0
        return DevCheckResult(
            passed: ok,
            detail: ok ? "Racked frame correctly flagged — Δdiagonal=\(String(format: "%.0f", reveal.diagonalDeltaMM))mm"
                       : "Expected out-of-square flag, got Δdiagonal=\(reveal.diagonalDeltaMM)mm isSquare=\(reveal.isSquareWithinTolerance)"
        )
    }

    static func quoteAttachmentCopyMatchesSpecFormat() -> DevCheckResult {
        // §3.3's own example: "Replace kitchen sink unit — void measured
        // 562 × 448 × 585 mm" — asserts the generator produces exactly that
        // shape (mm-rounded, em-dash separated) so what flows into
        // jobDescription/claudeContext reads the way the spec intends.
        let dims = SpaceDimensions(width: 0.562, height: 0.448, depth: 0.585, scanMethod: .lidar)
        let note = SpaceQuoteAttachment.note(itemLabel: "Replace kitchen sink unit", dimensions: dims)
        let expected = "Replace kitchen sink unit — void measured 562 × 448 × 585 mm"
        let ok = note == expected
        return DevCheckResult(
            passed: ok,
            detail: ok ? "Copy matches §3.3 exactly: \"\(note)\"" : "Got \"\(note)\", expected \"\(expected)\""
        )
    }

    // MARK: Phase 5 — shared 3D viewer (§6)

    static func dimensionLabelsFadeAtCorrectDistance() -> DevCheckResult {
        // §6.3: labels visible inside 2.5x bounding radius, hidden beyond it.
        // Exercises the pure threshold check pulled out of
        // ScanSceneKitView.Coordinator.updateLabelVisibility.
        let radius: Float = 4.0
        let closeIn  = ScanSceneKitView.Coordinator.shouldShowLabels(zoomDistance: radius * 2.0, boundingRadius: radius)
        let farOut   = ScanSceneKitView.Coordinator.shouldShowLabels(zoomDistance: radius * 3.0, boundingRadius: radius)
        let atEdge   = ScanSceneKitView.Coordinator.shouldShowLabels(zoomDistance: radius * 2.5, boundingRadius: radius)
        let ok = closeIn && !farOut && !atEdge
        return DevCheckResult(
            passed: ok,
            detail: ok ? "2.0x→visible, 2.5x→hidden, 3.0x→hidden (correct fade threshold)"
                       : "closeIn(2.0x)=\(closeIn) atEdge(2.5x)=\(atEdge) farOut(3.0x)=\(farOut) — expected true/false/false"
        )
    }

    // MARK: Phase 6 — Full Works / floor plan renderer (§4, §5.2)

    /// A simple 4×3m rectangular room fixture — used both by the Dev Tools
    /// "preview renderer" row and reused below by the projection-math checks
    /// so there's one canonical fixture room, not several slightly different
    /// ones drifting apart over time.
    static func fixtureWalls() -> [PlanWallSample] {
        [
            PlanWallSample(id: "north", start: SIMD2(0, 0), end: SIMD2(4, 0)),
            PlanWallSample(id: "east",  start: SIMD2(4, 0), end: SIMD2(4, 3)),
            PlanWallSample(id: "south", start: SIMD2(4, 3), end: SIMD2(0, 3)),
            PlanWallSample(id: "west",  start: SIMD2(0, 3), end: SIMD2(0, 0)),
        ]
    }

    static func fixtureFloorPlan() -> FloorPlan2D {
        let door = PlanOpeningSample(position: SIMD2(2, 0), widthMetres: 0.9)
        let window = PlanOpeningSample(position: SIMD2(4, 1.5), widthMetres: 1.2)
        return FloorPlan2DBuilder.build(
            walls: fixtureWalls(), doors: [door], windows: [window], roomName: "Kitchen"
        )
    }

    static func floorPlanBuilderProjectsRectangularRoom() -> DevCheckResult {
        let plan = fixtureFloorPlan()
        let ok = plan.walls.count == 4
            && plan.dimensionStrings.filter { !$0.isOverall }.count == 4
            && plan.dimensionStrings.filter { $0.isOverall }.count == 2
            && plan.roomLabels.count == 1
            && abs(plan.roomLabels[0].floorAreaSqMetres - 12.0) < 0.1
        return DevCheckResult(
            passed: ok,
            detail: ok ? "4×3m fixture → 4 walls, 6 dimension strings, area \(String(format: "%.1f", plan.roomLabels.first?.floorAreaSqMetres ?? 0))m²"
                       : "Got \(plan.walls.count) walls, \(plan.dimensionStrings.count) dims, area \(plan.roomLabels.first?.floorAreaSqMetres ?? -1)m² — expected 4 walls, 6 dims, ~12m²"
        )
    }

    static func floorPlanBuilderAssociatesOpeningsToNearestWall() -> DevCheckResult {
        let walls = fixtureWalls()
        // A point at (2, 0) sits exactly on the "north" wall (0,0)→(4,0) —
        // nearestWall must resolve to that wall, not any other.
        guard let nearest = FloorPlan2DBuilder.nearestWall(to: SIMD2(2, 0), in: walls) else {
            return DevCheckResult(passed: false, detail: "nearestWall returned nil")
        }
        let ok = nearest.id == "north"
        return DevCheckResult(
            passed: ok,
            detail: ok ? "Point (2,0) correctly associated with the north wall"
                       : "Point (2,0) associated with '\(nearest.id)', expected 'north'"
        )
    }

    static func floorPlanOverallDimensionsMatchBoundingBox() -> DevCheckResult {
        let walls = fixtureWalls()
        let overall = FloorPlan2DBuilder.overallBoundingDimensions(walls: walls)
        let ok = overall.count == 2
            && overall.contains { abs($0.valueMetres - 4.0) < 0.01 }
            && overall.contains { abs($0.valueMetres - 3.0) < 0.01 }
        return DevCheckResult(
            passed: ok,
            detail: ok ? "4×3m room → overall dimensions 4.0m and 3.0m"
                       : "Got \(overall.map { $0.valueMetres }) — expected [4.0, 3.0]"
        )
    }

    static func fullWorksCSVEscapesSpecialCharacters() -> DevCheckResult {
        guard #available(iOS 17.0, *) else {
            return DevCheckResult(passed: true, detail: "Skipped — FullWorksOutput requires iOS 17+ (not available on this OS)")
        }
        // A room name containing a comma is exactly the input that would
        // silently corrupt the column count if csvField didn't quote it —
        // "Kitchen, Utility" un-escaped would read as two CSV columns.
        let plain = FullWorksOutput.csvField("Kitchen")
        let withComma = FullWorksOutput.csvField("Kitchen, Utility")
        let withQuote = FullWorksOutput.csvField("12\" void")
        let ok = plain == "Kitchen"
            && withComma == "\"Kitchen, Utility\""
            && withQuote == "\"12\"\" void\""
        return DevCheckResult(
            passed: ok,
            detail: ok ? "Comma/quote fields correctly quoted and escaped"
                       : "plain=\(plain) withComma=\(withComma) withQuote=\(withQuote)"
        )
    }

    static func fullWorksCSVRoundTripsDimensionSchedule() -> DevCheckResult {
        guard #available(iOS 17.0, *) else {
            return DevCheckResult(passed: true, detail: "Skipped — FullWorksOutput requires iOS 17+ (not available on this OS)")
        }
        let schedule = [
            RoomDimensionRecord(roomName: "Kitchen", length: 4.2, width: 3.1, height: 2.4,
                                 floorArea: 13.02, wallArea: 35.04, doorCount: 1, windowCount: 2),
            RoomDimensionRecord(roomName: "Lounge, Diner", length: 5.0, width: 4.0, height: 2.4,
                                 floorArea: 20.0, wallArea: 43.2, doorCount: 2, windowCount: 3),
        ]
        let csv = FullWorksOutput.csvString(for: schedule)
        let lines = csv.components(separatedBy: "\n")
        let ok = lines.count == 3   // header + 2 rows
            && lines[0] == "Room,Length (m),Width (m),Height (m),Floor Area (m²),Wall Area (m²),Doors,Windows"
            && lines[1] == "Kitchen,4.20,3.10,2.40,13.02,35.04,1,2"
            && lines[2] == "\"Lounge, Diner\",5.00,4.00,2.40,20.00,43.20,2,3"
        return DevCheckResult(
            passed: ok,
            detail: ok ? "2-room schedule → 3 CSV lines, comma-containing name correctly quoted"
                       : "Got \(lines.count) lines: \(lines)"
        )
    }

    // MARK: Phase 7 — mode picker, persistence & history (§1, §7)

    static func savedQuoteDecodesOldJSONWithSafeDefaults() -> DevCheckResult {
        // Simulates a SavedQuote written before scanMode/scanArtifactURL
        // existed — every field up to and including `sections` (the last
        // field added before this phase), nothing newer.
        let oldShapeJSON = """
        {"id":"abc-123","savedAt":\(Date().timeIntervalSinceReferenceDate),
         "customerName":"Mr Smith","jobDescription":"Rewire","roomType":"bedroom",
         "floorArea":12.5,"labourDays":2,"labourRate":280,"labourTotal":560,
         "items":[],"subtotal":560,"vatRate":20,"vatAmount":112,"grandTotal":672,
         "notes":"","sections":[]}
        """.data(using: .utf8)!

        do {
            let decoded = try JSONDecoder().decode(SavedQuote.self, from: oldShapeJSON)
            let ok = decoded.scanMode == "room" && decoded.scanArtifactURL == nil && decoded.thumbnailURL == nil
            return DevCheckResult(
                passed: ok,
                detail: ok ? "Old-shape JSON decoded with scanMode=\"room\", scanArtifactURL=nil"
                           : "Got scanMode=\(decoded.scanMode) scanArtifactURL=\(decoded.scanArtifactURL ?? "nil")"
            )
        } catch {
            return DevCheckResult(passed: false, detail: "Threw on old-shape JSON: \(error)")
        }
    }

    static func savedQuoteThumbnailURLDerivesFromArtifactURL() -> DevCheckResult {
        let quote = SavedQuote(
            id: "x", savedAt: Date(), customerName: "", jobDescription: "", roomType: "bedroom",
            floorArea: 10, labourDays: 1, labourRate: 280, labourTotal: 280, items: [],
            subtotal: 280, vatRate: 20, vatAmount: 56, grandTotal: 336, notes: "",
            scanMode: "space", scanArtifactURL: "file:///Documents/aq_scans/abc/model.usdz"
        )
        let ok = quote.thumbnailURL?.absoluteString == "file:///Documents/aq_scans/abc/thumb.jpg"
            && quote.scanModeDisplayLabel == "Space"
        return DevCheckResult(
            passed: ok,
            detail: ok ? "thumbnailURL correctly derived as thumb.jpg alongside model.usdz"
                       : "Got \(quote.thumbnailURL?.absoluteString ?? "nil")"
        )
    }

    static func scanStorageCleanupRespectsRetentionWindow() -> DevCheckResult {
        let now = Date()
        let recentDate = Calendar.current.date(byAdding: .day, value: -30, to: now)!
        let oldDate = Calendar.current.date(byAdding: .day, value: -120, to: now)!
        let borderlineDate = Calendar.current.date(byAdding: .day, value: -91, to: now)!

        let recentEligible = ScanStorageManager.isEligibleForCleanup(modificationDate: recentDate, now: now, retentionDays: 90)
        let oldEligible = ScanStorageManager.isEligibleForCleanup(modificationDate: oldDate, now: now, retentionDays: 90)
        let borderlineEligible = ScanStorageManager.isEligibleForCleanup(modificationDate: borderlineDate, now: now, retentionDays: 90)

        let ok = !recentEligible && oldEligible && borderlineEligible
        return DevCheckResult(
            passed: ok,
            detail: ok ? "30-day-old kept, 91/120-day-old correctly eligible for cleanup"
                       : "recent(30d)=\(recentEligible) borderline(91d)=\(borderlineEligible) old(120d)=\(oldEligible) — expected false/true/true"
        )
    }
}
#endif
