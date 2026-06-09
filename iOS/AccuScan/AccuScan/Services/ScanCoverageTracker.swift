import ARKit
import UIKit

// MARK: - ScanCoverageTracker
//
// Tracks real-time room scan coverage by analysing ARFrames.
// Ported from AccuQuote to ensure identical scan UX across both apps.
//
// Three weighted axes → single 0–1 Float:
//   Azimuth  60%  — 24 × 15° sectors around the room
//   Vertical 30%  — has each sector seen both ceiling zone and floor zone
//   Ceiling  10%  — cumulative upward dwell time
//
// Hard gates: 100% only when all 24 sectors hit + 10 vertically swept +
// ceiling seen + 2m walked.

@MainActor
final class ScanCoverageTracker: ObservableObject {

    @Published private(set) var coverage:   Float = 0
    @Published private(set) var sectors:    [SectorState] = Array(
        repeating: SectorState(azimuthHit: false, verticallySwept: false),
        count: sectorCount
    )
    @Published private(set) var isComplete: Bool = false

    static let sectorCount = 24

    // Internal tracking state
    private var azimuthHit      = Array(repeating: false, count: sectorCount)
    private var sectorSeenHigh  = Array(repeating: false, count: sectorCount)
    private var sectorSeenLow   = Array(repeating: false, count: sectorCount)
    private var ceilingDwell:   Double = 0
    private var lastFrameTime:  Double? = nil
    private var totalDistance:  Float  = 0
    private var lastCamPos:     SIMD3<Float>? = nil
    private var camSamples:     [SIMD2<Float>] = []
    private var roomCentre:     SIMD2<Float>   = .zero
    private var centreReady     = false

    private static let centreSampleCount  = 60
    private static let highPitch: Float   =  0.20
    private static let lowPitch:  Float   = -0.20
    private static let ceilingPitch: Float = 0.55
    private static let ceilingNeeded: Double = 0.8
    private static let verticalGate  = 10
    private static let distanceGate: Float = 2.0

    func reset() {
        azimuthHit      = Array(repeating: false, count: Self.sectorCount)
        sectorSeenHigh  = Array(repeating: false, count: Self.sectorCount)
        sectorSeenLow   = Array(repeating: false, count: Self.sectorCount)
        ceilingDwell    = 0
        lastFrameTime   = nil
        totalDistance   = 0
        lastCamPos      = nil
        camSamples      = []
        roomCentre      = .zero
        centreReady     = false
        coverage        = 0
        isComplete      = false
        sectors = Array(repeating: SectorState(azimuthHit: false, verticallySwept: false),
                        count: Self.sectorCount)
    }

    func ingest(_ frame: ARFrame) {
        let t   = frame.camera.transform
        let pos = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
        let xz  = SIMD2<Float>(pos.x, pos.z)

        if let last = lastCamPos { totalDistance += simd_distance(pos, last) }
        lastCamPos = pos

        if !centreReady {
            camSamples.append(xz)
            if camSamples.count >= Self.centreSampleCount {
                let xs = camSamples.map { $0.x }.sorted()
                let ys = camSamples.map { $0.y }.sorted()
                let m  = camSamples.count / 2
                roomCentre  = SIMD2(xs[m], ys[m])
                centreReady = true
            }
        }

        let fwd = SIMD3<Float>(-t.columns.2.x, -t.columns.2.y, -t.columns.2.z)

        let rel = xz - roomCentre
        let azRad: Float = centreReady && simd_length(rel) > 0.4
            ? atan2(rel.x, rel.y)
            : atan2(fwd.x, fwd.z)
        let azDeg = (azRad * 180 / Float.pi + 360).truncatingRemainder(dividingBy: 360)
        let sector = Int(azDeg / (360 / Float(Self.sectorCount))) % Self.sectorCount

        azimuthHit[sector] = true

        let pitch = asin(max(-1, min(1, fwd.y)))
        if pitch >  Self.highPitch   { sectorSeenHigh[sector] = true }
        if pitch <  Self.lowPitch    { sectorSeenLow[sector]  = true }

        let now = frame.timestamp
        if let last = lastFrameTime, pitch > Self.ceilingPitch {
            ceilingDwell += now - last
        }
        lastFrameTime = now

        recompute()
    }

    private func recompute() {
        let azCount  = azimuthHit.filter { $0 }.count
        let swCount  = zip(sectorSeenHigh, sectorSeenLow).filter { $0 && $1 }.count
        let ceilFrac = Float(min(1.0, ceilingDwell / Self.ceilingNeeded))
        let distFrac = min(1.0, totalDistance / Self.distanceGate)

        var raw = Float(azCount) / Float(Self.sectorCount) * 0.60
               + Float(swCount) / Float(Self.sectorCount) * 0.30
               + ceilFrac * 0.10

        let gated = azCount == Self.sectorCount
                 && swCount >= Self.verticalGate
                 && ceilingDwell >= Self.ceilingNeeded
                 && distFrac >= 1.0
        if !gated { raw = min(raw, 0.99) }

        let newCov  = max(coverage, min(1.0, raw))
        let newSecs = (0..<Self.sectorCount).map { i in
            SectorState(azimuthHit: azimuthHit[i],
                        verticallySwept: sectorSeenHigh[i] && sectorSeenLow[i])
        }
        coverage = newCov
        sectors  = newSecs
        if newCov >= 1.0 && !isComplete {
            isComplete = true
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }
}

// MARK: - SectorState

struct SectorState {
    let azimuthHit:      Bool
    let verticallySwept: Bool
}
