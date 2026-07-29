import Foundation
import RoomPlan
import simd

// MARK: - ScanQualityGate (Tri-Mode Scanning build spec §5.4)
//
// Deterministic detection heuristics, run once at capture end, before a scan
// is ever allowed to reach ScanCoordinator's .complete state.
//
// Two layers, deliberately kept separate:
//   1. Pure decision logic (the `evaluate*(...)` functions below) — takes
//      plain values (Bool/Float/Double), no RoomPlan types. This is what
//      DevToolsChecks exercises with synthetic fixtures, because...
//   2. CapturedRoom extraction (`WallSample.samples(from:)` etc.) — thin
//      adapters that read RoomPlan's actual data. CapturedRoom/Surface have
//      no public initializer (decode-only, framework-constructed), so this
//      layer can only be exercised by a real scan, never a synthetic
//      fixture — see DevToolsView's "replay last scan" row instead.
//
// Room mode reads RoomPlan's own confidence/edge signals directly —
// Surface.completedEdges tells you which sides RoomPlan itself couldn't
// confirm close against a neighbour, which has no equivalent in the app's
// abstract Surface model (that model's `edges` is a generic adjacency graph
// for Space/Full Works' raw ARKit mesh, where no such built-in signal
// exists and adjacency must be computed from the mesh itself). Both paths
// produce the same ScanConfidence/ScanIssue output type.

enum ScanQualityGate {

    // MARK: - CapturedRoom extraction (thin adapter, real-scan-only)

    static func evaluate(capturedRoom: CapturedRoom) -> ScanConfidence {
        let wallSamples = capturedRoom.walls.map(WallSample.init)
        let doorSamples = capturedRoom.doors.map { OpeningSample($0, isDoor: true) }
        let windowSamples = capturedRoom.windows.map { OpeningSample($0, isDoor: false) }
        // CapturedRoom.floors requires iOS 17+ (deployment target here is 16.0) —
        // mirrors the same #available guard AccuScan's ScanSession.swift already
        // uses for the identical reason. Floor confidence simply isn't checked
        // on iOS 16 devices; walls/doors/windows still are.
        let floorSamples: [SurfaceConfidenceSample]
        if #available(iOS 17.0, *) {
            floorSamples = capturedRoom.floors.map(SurfaceConfidenceSample.init)
        } else {
            floorSamples = []
        }

        return evaluate(walls: wallSamples, doors: doorSamples, windows: windowSamples, floors: floorSamples)
    }

    // MARK: - Pure decision logic (fixture-testable, no RoomPlan types)

    static func evaluate(
        walls: [WallSample],
        doors: [OpeningSample] = [],
        windows: [OpeningSample] = [],
        floors: [SurfaceConfidenceSample] = []
    ) -> ScanConfidence {
        var issues: [ScanIssue] = []

        issues += openLoopIssues(walls: walls)
        issues += lowConfidenceIssues(walls: walls)
        issues += lowConfidenceIssues(floors: floors)
        issues += suspiciousDimensionIssues(walls: walls)
        issues += unmeasuredOpeningIssues(doors: doors, windows: windows)

        let overallScore = computeOverallScore(wallCount: walls.count, issueCount: issues.count)
        return ScanConfidence(overallScore: overallScore, issues: issues.sorted(by: severityThenScoreOrder))
    }

    // Open-loop / non-manifold walls (heuristic 1): a wall whose left/right
    // side isn't marked complete means RoomPlan itself couldn't confirm that
    // side closes against a neighbouring surface — "the room that doesn't
    // close." Top/bottom (floor/ceiling joins) are excluded; a real room can
    // legitimately have an open top edge mid-wall (e.g. a loft void) without
    // that meaning the floor plan doesn't close — that case is covered by
    // the confidence check instead.
    private static func openLoopIssues(walls: [WallSample]) -> [ScanIssue] {
        walls.compactMap { wall in
            guard !wall.leftEdgeClosed || !wall.rightEdgeClosed else { return nil }
            return ScanIssue(
                kind: .openLoop, severity: .blocking, worldAnchor: wall.worldPosition,
                affectedSurfaceIDs: [wall.id],
                hint: "This wall doesn't connect to its neighbour — walk back and re-scan this corner."
            )
        }
    }

    // Low-confidence surfaces (heuristic 3): RoomPlan's own 3-level
    // confidence, not a numeric threshold — .low is blocking (maps onto the
    // spec's "< 0.5"), .medium is a warning, .high never generates an issue.
    private static func lowConfidenceIssues(walls: [WallSample]) -> [ScanIssue] {
        walls.compactMap { wall in
            issue(for: wall.confidence, id: wall.id, position: wall.worldPosition, kindLabel: "wall")
        }
    }

    private static func lowConfidenceIssues(floors: [SurfaceConfidenceSample]) -> [ScanIssue] {
        floors.compactMap { floor in
            issue(for: floor.confidence, id: floor.id, position: floor.worldPosition, kindLabel: "floor")
        }
    }

    private static func issue(for confidence: SampleConfidence, id: String, position: SIMD3<Float>, kindLabel: String) -> ScanIssue? {
        switch confidence {
        case .low:
            return ScanIssue(
                kind: .lowConfidenceSurface, severity: .blocking, worldAnchor: position, affectedSurfaceIDs: [id],
                hint: "This \(kindLabel) wasn't scanned clearly — move closer and re-scan it."
            )
        case .medium:
            return ScanIssue(
                kind: .lowConfidenceSurface, severity: .warning, worldAnchor: position, affectedSurfaceIDs: [id],
                hint: "This \(kindLabel)'s measurement may be slightly off — re-scan for full precision."
            )
        case .high:
            return nil
        }
    }

    // Suspicious dimensions (heuristic 5): sanity bounds on individual wall
    // spans. Ceiling-height and isoperimetric checks need the assembled
    // RoomDimensions rather than a single wall in isolation, so those stay
    // in ScanCoordinator.resultFromLiDAR's existing clamps — this heuristic
    // only adds what that code doesn't already cover: a structurally-valid-
    // but-implausible wall length.
    private static func suspiciousDimensionIssues(walls: [WallSample]) -> [ScanIssue] {
        walls.compactMap { wall in
            guard wall.lengthMetres.isFinite, wall.lengthMetres > 0, wall.lengthMetres < 0.2 else { return nil }
            return ScanIssue(
                kind: .suspiciousDimension, severity: .warning, worldAnchor: wall.worldPosition, affectedSurfaceIDs: [wall.id],
                hint: "This wall measured suspiciously short (\(String(format: "%.2f", wall.lengthMetres))m) — check it wasn't cut off."
            )
        }
    }

    // Unmeasured openings (heuristic 4): a door/window RoomPlan detected but
    // gave .low confidence to, meaning its full extent likely wasn't in
    // frame long enough to measure properly.
    private static func unmeasuredOpeningIssues(doors: [OpeningSample], windows: [OpeningSample]) -> [ScanIssue] {
        (doors + windows).compactMap { opening in
            guard opening.confidence == .low else { return nil }
            let label = opening.isDoor ? "door" : "window"
            return ScanIssue(
                kind: .unmeasuredOpening, severity: .warning, worldAnchor: opening.worldPosition, affectedSurfaceIDs: [opening.id],
                hint: "This \(label) wasn't fully in view — re-scan it straight-on to get its exact size."
            )
        }
    }

    // Weighted composite: start at 1.0, subtract per-issue penalty. Mirrors
    // ScanConfidence.isPassing's own 0.85 threshold — a single blocking
    // issue already fails isPassing regardless of score via the
    // `!issues.contains` check, so this score is primarily the "how close"
    // progress signal shown in the Review screen, not the pass/fail decision.
    static func computeOverallScore(wallCount: Int, issueCount: Int) -> Float {
        guard wallCount > 0 else { return issueCount == 0 ? 1.0 : 0.0 }
        let penalty = Float(issueCount) * 0.12
        return max(0.0, 1.0 - penalty)
    }

    private static func severityThenScoreOrder(_ a: ScanIssue, _ b: ScanIssue) -> Bool {
        severityRank(a.severity) < severityRank(b.severity)
    }

    private static func severityRank(_ s: Severity) -> Int {
        switch s {
        case .blocking: return 0
        case .warning:  return 1
        case .info:     return 2
        }
    }
}

// MARK: - Fixture-testable sample types
//
// Plain-value shadows of the RoomPlan data the gate actually needs. Real
// scans build these from CapturedRoom.Surface (see the `init` extensions
// below); DevToolsChecks builds them directly with literal values.

enum SampleConfidence {
    case low, medium, high
}

struct WallSample {
    let id: String
    let worldPosition: SIMD3<Float>
    let lengthMetres: Float
    let leftEdgeClosed: Bool
    let rightEdgeClosed: Bool
    let confidence: SampleConfidence

    init(id: String = UUID().uuidString, worldPosition: SIMD3<Float> = .zero, lengthMetres: Float,
         leftEdgeClosed: Bool, rightEdgeClosed: Bool, confidence: SampleConfidence) {
        self.id = id
        self.worldPosition = worldPosition
        self.lengthMetres = lengthMetres
        self.leftEdgeClosed = leftEdgeClosed
        self.rightEdgeClosed = rightEdgeClosed
        self.confidence = confidence
    }

    init(_ surface: CapturedRoom.Surface) {
        id = surface.identifier.uuidString
        worldPosition = Self.worldPosition(of: surface)
        lengthMetres = surface.dimensions.x
        leftEdgeClosed = surface.completedEdges.contains(.left)
        rightEdgeClosed = surface.completedEdges.contains(.right)
        confidence = SampleConfidence(surface.confidence)
    }

    private static func worldPosition(of surface: CapturedRoom.Surface) -> SIMD3<Float> {
        let t = surface.transform
        return SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
    }
}

struct SurfaceConfidenceSample {
    let id: String
    let worldPosition: SIMD3<Float>
    let confidence: SampleConfidence

    init(id: String = UUID().uuidString, worldPosition: SIMD3<Float> = .zero, confidence: SampleConfidence) {
        self.id = id
        self.worldPosition = worldPosition
        self.confidence = confidence
    }

    init(_ surface: CapturedRoom.Surface) {
        id = surface.identifier.uuidString
        let t = surface.transform
        worldPosition = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
        confidence = SampleConfidence(surface.confidence)
    }
}

struct OpeningSample {
    let id: String
    let worldPosition: SIMD3<Float>
    let confidence: SampleConfidence
    let isDoor: Bool

    init(id: String = UUID().uuidString, worldPosition: SIMD3<Float> = .zero, confidence: SampleConfidence, isDoor: Bool) {
        self.id = id
        self.worldPosition = worldPosition
        self.confidence = confidence
        self.isDoor = isDoor
    }

    init(_ surface: CapturedRoom.Surface, isDoor: Bool = true) {
        id = surface.identifier.uuidString
        let t = surface.transform
        worldPosition = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
        confidence = SampleConfidence(surface.confidence)
        self.isDoor = isDoor
    }
}

private extension SampleConfidence {
    init(_ roomPlanConfidence: CapturedRoom.Confidence) {
        switch roomPlanConfidence {
        case .low:    self = .low
        case .medium: self = .medium
        case .high:   self = .high
        @unknown default: self = .medium
        }
    }
}
