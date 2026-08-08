import Foundation
import simd

// MARK: - ScanConfidence (Tri-Mode Scanning build spec §5.4)
//
// Computed once, at capture end, before a scan is ever allowed to reach
// ScanCoordinator's .complete state. If isPassing is false the coordinator
// enters .needsReview(ScanResult) instead — see the Quality Gate phase of
// the build plan for where this gets wired into the state machine.
//
// Detection heuristics that populate `issues` are pure functions over
// Surface/mesh data (no @MainActor, no view code) so they're independently
// unit-testable against fixture geometry — see ScanQualityGate.swift.

struct ScanConfidence: Codable {
    var overallScore: Float   // 0…1, weighted composite
    var issues: [ScanIssue]   // ordered worst-first

    var isPassing: Bool {
        overallScore >= 0.85 && !issues.contains { $0.severity == .blocking }
    }

    init(overallScore: Float, issues: [ScanIssue]) {
        self.overallScore = overallScore
        self.issues = issues
    }

    // Backwards-compatible decode: a ScanResult saved before this feature
    // existed simply has no confidence report — treat it as a pass rather
    // than fail-closed, since the scan already shipped to the user as
    // .complete under the old code path.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        overallScore = (try? c.decode(Float.self, forKey: .overallScore)) ?? 1.0
        issues = (try? c.decode([ScanIssue].self, forKey: .issues)) ?? []
    }
}

struct ScanIssue: Codable, Identifiable {
    let id: String
    let kind: IssueKind
    let severity: Severity
    var worldAnchor: SIMD3<Float>     // where it is in 3D — drives the pulsing
                                        // marker in the Review & Guided Re-scan
                                        // screen (§5.4 step 2)
    var affectedSurfaceIDs: [String]
    var hint: String                  // plain-English copy, e.g. "This corner
                                        // didn't close — walk back and scan it"

    init(id: String = UUID().uuidString, kind: IssueKind, severity: Severity,
         worldAnchor: SIMD3<Float>, affectedSurfaceIDs: [String], hint: String) {
        self.id = id
        self.kind = kind
        self.severity = severity
        self.worldAnchor = worldAnchor
        self.affectedSurfaceIDs = affectedSurfaceIDs
        self.hint = hint
    }
}

enum IssueKind: String, Codable {
    case openLoop              // wall edge not shared by two surfaces at a corner
    case lowConfidenceSurface  // RoomPlan/ARKit per-surface confidence < 0.5
    case holeInMesh            // boundary loop not at an expected opening
    case unmeasuredOpening     // door/window whose full extent was never in frame
    case suspiciousDimension   // outside sanity bounds (ceiling height, wall length, isoperimetric check)
    case driftDetected         // Full Works: re-entry doorway disagrees with prior position by > 8cm
    case insufficientCoverage // Space mode: filled voxels / expected < 92%
}

enum Severity: String, Codable {
    case blocking   // hard-blocks export/quote generation until resolved
    case warning    // may be accepted via "Use anyway", persists an acceptance note
    case info
}
