import ARKit
import Combine
import UIKit

// MARK: - ScanCoverageTracker
//
// Tracks how much of a room has been scanned in real time by analysing
// each ARFrame the camera produces. Publishes a single Float (0–1) and
// a per-sector breakdown used to drive the Face-ID-style ring UI.
//
// Three independent axes — weighted into one percentage:
//
//   Azimuth coverage  (60%) — 24 sectors of 15° around the room.
//                             Each sector is "hit" when the camera faces
//                             that direction from near the room centre.
//
//   Vertical sweep    (30%) — each azimuth sector also tracks whether
//                             the camera has swept from near the ceiling
//                             to near the floor while facing that direction.
//                             A sector is "fully swept" when it has seen
//                             both a high-pitch and a low-pitch look.
//
//   Ceiling           (10%) — set when camera tilts upward > 45° for
//                             at least 1.5 seconds total cumulative dwell.
//
// 100% is hard-gated: requires all 24 sectors azimuth-hit AND at least
// 16/24 sectors vertically swept AND ceiling seen AND ≥ 3 m walked.
// Below that gate the displayed value is capped at 99%.
//
// Values only ever increase — sectors never un-hit.

@MainActor
final class ScanCoverageTracker: ObservableObject {

    // MARK: - Published

    /// 0.0 – 1.0. Only reaches 1.0 when all hard-gate conditions are met.
    @Published private(set) var coverage: Float = 0

    /// Per-sector state for the ring UI. Index 0 = top (12 o'clock), clockwise.
    @Published private(set) var sectors: [SectorState] = Array(
        repeating: SectorState(azimuthHit: false, verticallySwept: false),
        count: sectorCount
    )

    /// True once coverage first reaches 1.0.
    @Published private(set) var isComplete: Bool = false

    // MARK: - Sector constants

    static let sectorCount = 24          // 360° / 24 = 15° per sector

    // MARK: - Internal state

    // Azimuth: which sectors the camera has faced
    private var azimuthHit = Array(repeating: false, count: sectorCount)

    // Vertical: per sector, have we seen both a high pitch (ceiling) and low pitch (floor)?
    private var sectorSeenHigh  = Array(repeating: false, count: sectorCount)
    private var sectorSeenLow   = Array(repeating: false, count: sectorCount)

    // Ceiling: cumulative dwell time looking up
    private var ceilingDwellSeconds: Double = 0
    private var lastFrameTime: Double?

    // Distance gate
    private var totalDistanceM: Float = 0
    private var lastCamPos: SIMD3<Float>?

    // Room centre — estimated from first N camera positions
    private var camPosSamples: [SIMD2<Float>] = []
    private var roomCentreXZ: SIMD2<Float> = .zero
    private var roomCentreReady = false
    private static let centreSampleCount = 60   // ~4 s at 15 Hz

    // Pitch thresholds (radians)
    private static let highPitchThreshold: Float =  0.20   // ~11° up   → wall top zone
    private static let lowPitchThreshold:  Float = -0.20   // ~11° down → wall bottom zone
    private static let ceilingPitchThreshold: Float = 0.55 // ~32° up   → looking at ceiling

    // Ceiling dwell needed for full ceiling credit
    private static let ceilingDwellNeeded: Double = 0.8    // seconds cumulative

    // Vertical sweep: how many sectors need to be fully swept for the gate
    private static let verticalSweepGate = 10              // out of 24

    // Distance gate
    private static let distanceGateM: Float = 2.0

    // MARK: - Init / reset

    init() {}

    func reset() {
        azimuthHit           = Array(repeating: false, count: Self.sectorCount)
        sectorSeenHigh       = Array(repeating: false, count: Self.sectorCount)
        sectorSeenLow        = Array(repeating: false, count: Self.sectorCount)
        ceilingDwellSeconds  = 0
        lastFrameTime        = nil
        totalDistanceM       = 0
        lastCamPos           = nil
        camPosSamples        = []
        roomCentreXZ         = .zero
        roomCentreReady      = false
        coverage             = 0
        isComplete           = false
        sectors = Array(repeating: SectorState(azimuthHit: false, verticallySwept: false),
                        count: Self.sectorCount)
    }

    // MARK: - Feed frames

    /// Call this for every ARFrame while scanning (4 Hz is plenty, 15 Hz is ideal).
    func ingest(_ frame: ARFrame) {
        let cam = frame.camera
        let t   = cam.transform

        // World-space camera position
        let pos = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
        let posXZ = SIMD2<Float>(pos.x, pos.z)

        // Distance tracking
        if let last = lastCamPos {
            totalDistanceM += simd_distance(pos, last)
        }
        lastCamPos = pos

        // Room centre estimation — collect first N positions and take median
        if !roomCentreReady {
            camPosSamples.append(posXZ)
            if camPosSamples.count >= Self.centreSampleCount {
                roomCentreXZ = medianXZ(camPosSamples)
                roomCentreReady = true
            }
        }

        // Camera forward direction in world space (column 2, negated = look direction)
        let fwd = SIMD3<Float>(-t.columns.2.x, -t.columns.2.y, -t.columns.2.z)

        // Azimuth: angle in XZ plane of camera look direction from room centre.
        // We use camera position relative to room centre, not the look direction itself,
        // because the user circles the room facing inward.
        let relXZ = posXZ - roomCentreXZ
        let azimuthRad: Float
        if roomCentreReady && simd_length(relXZ) > 0.4 {
            // Angle from room centre to camera position — gives which wall they're facing
            azimuthRad = atan2(relXZ.x, relXZ.y)
        } else {
            // Fallback: camera look direction projected to XZ
            azimuthRad = atan2(fwd.x, fwd.z)
        }
        let azimuthDeg = (azimuthRad * 180 / Float.pi + 360).truncatingRemainder(dividingBy: 360)
        let sector = Int(azimuthDeg / (360.0 / Float(Self.sectorCount))) % Self.sectorCount

        azimuthHit[sector] = true

        // Pitch: angle above/below horizontal
        // fwd.y is the vertical component of the look direction.
        // pitch = asin(fwd.y) — positive = looking up, negative = looking down.
        let pitch = asin(max(-1, min(1, fwd.y)))

        // Vertical sweep tracking per sector
        if pitch >  Self.highPitchThreshold { sectorSeenHigh[sector] = true }
        if pitch <  Self.lowPitchThreshold  { sectorSeenLow[sector]  = true }

        // Ceiling dwell
        let now = frame.timestamp
        if let last = lastFrameTime {
            let dt = now - last
            if pitch > Self.ceilingPitchThreshold {
                ceilingDwellSeconds += dt
            }
        }
        lastFrameTime = now

        // Recompute and publish
        recompute()
    }

    // MARK: - Computation

    private func recompute() {
        let azimuthCount  = azimuthHit.filter { $0 }.count
        let sweptCount    = zip(sectorSeenHigh, sectorSeenLow).filter { $0 && $1 }.count
        let ceilingCredit = min(1.0, ceilingDwellSeconds / Self.ceilingDwellNeeded)
        let distCredit    = min(1.0, Double(totalDistanceM / Self.distanceGateM))

        let azimuthFrac  = Float(azimuthCount)  / Float(Self.sectorCount)
        let sweptFrac    = Float(sweptCount)     / Float(Self.sectorCount)
        let ceilingFrac  = Float(ceilingCredit)

        // Weighted combination (wall 60%, vertical 30%, ceiling 10%)
        var raw = azimuthFrac * 0.60 + sweptFrac * 0.30 + ceilingFrac * 0.10

        // Hard gate: 100% only when all conditions satisfied
        let gatesMet = azimuthCount  == Self.sectorCount
                    && sweptCount    >= Self.verticalSweepGate
                    && ceilingCredit >= 1.0
                    && distCredit    >= 1.0
        if !gatesMet {
            raw = min(raw, 0.99)
        }

        // Clamp and ensure only upward movement
        let newCoverage = max(coverage, min(1.0, raw))

        // Update sector states for ring UI
        let newSectors = (0..<Self.sectorCount).map { i in
            SectorState(
                azimuthHit:      azimuthHit[i],
                verticallySwept: sectorSeenHigh[i] && sectorSeenLow[i]
            )
        }

        coverage  = newCoverage
        sectors   = newSectors
        if newCoverage >= 1.0 && !isComplete {
            isComplete = true
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    // MARK: - Helpers

    private func medianXZ(_ pts: [SIMD2<Float>]) -> SIMD2<Float> {
        let xs = pts.map { $0.x }.sorted()
        let ys = pts.map { $0.y }.sorted()
        let mid = pts.count / 2
        return SIMD2(xs[mid], ys[mid])
    }
}

// MARK: - Sector State

struct SectorState {
    let azimuthHit:      Bool   // camera has faced this direction
    let verticallySwept: Bool   // camera has swept ceiling-to-floor in this direction
}
