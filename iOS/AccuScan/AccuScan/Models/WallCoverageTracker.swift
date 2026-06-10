import RoomPlan
import simd

// MARK: - TrackedWall

struct TrackedWall: Identifiable {
    let id: UUID
    let insertionOrder: Int
    let roomPlanWall: CapturedRoom.Wall
    var confidence: CapturedRoom.Confidence
    var highlightState: HighlightState
    var coveragePct: Float
    var worldPosition: simd_float3
    var worldSize: simd_float3
    var worldTransform: simd_float4x4
    var topLeftCorner:     simd_float3
    var topRightCorner:    simd_float3
    var bottomLeftCorner:  simd_float3
    var bottomRightCorner: simd_float3

    enum HighlightState: Equatable {
        case none, partial, good, complete
    }
}

// MARK: - WallCoverageTracker

@MainActor
final class WallCoverageTracker {

    private var trackedWalls: [UUID: TrackedWall] = [:]
    private var insertionCounter = 0

    // Cached coverage — invalidated when any wall changes; avoids two reduce passes per tick
    private var coverageDirty = true
    private var cachedCoverage: Float = 0

    func update(from room: CapturedRoom) -> [TrackedWall] {
        for wall in room.walls {
            // C3/M6: skip walls with non-finite or non-positive geometry. RoomPlan
            // can emit degenerate transforms/dimensions mid-merge; these would
            // propagate NaN into Transform(matrix:), mesh generation and the
            // coverage denominator.
            let pos = simd_float3(wall.transform.columns.3.x,
                                  wall.transform.columns.3.y,
                                  wall.transform.columns.3.z)
            guard pos.x.isFinite, pos.y.isFinite, pos.z.isFinite,
                  wall.dimensions.x.isFinite, wall.dimensions.y.isFinite,
                  wall.dimensions.x > 0, wall.dimensions.y > 0 else { continue }

            let newHighlight = highlightState(for: wall.confidence)
            let newCoverage  = coveragePercent(for: wall.confidence)

            // M5: key by RoomPlan's stable wall identifier instead of fragile
            // spatial proximity. Proximity matching duplicated walls that shifted
            // >15 cm/tick, growing trackedWalls unbounded with ghost entries.
            let key = wall.identifier

            if var existing = trackedWalls[key] {
                guard existing.confidence != wall.confidence else { continue }
                existing.confidence     = wall.confidence
                existing.highlightState = newHighlight
                existing.coveragePct    = newCoverage
                existing.worldPosition  = pos
                existing.worldSize      = simd_float3(wall.dimensions.x, wall.dimensions.y, 0.1)
                existing.worldTransform = wall.transform
                let corners             = extractCorners(wall: wall)
                existing.topLeftCorner     = corners.topLeft
                existing.topRightCorner    = corners.topRight
                existing.bottomLeftCorner  = corners.bottomLeft
                existing.bottomRightCorner = corners.bottomRight
                trackedWalls[key]          = existing
                coverageDirty = true
            } else {
                insertionCounter += 1
                let corners = extractCorners(wall: wall)
                trackedWalls[key] = TrackedWall(
                    id:             key,
                    insertionOrder: insertionCounter,
                    roomPlanWall:   wall,
                    confidence:     wall.confidence,
                    highlightState: newHighlight,
                    coveragePct:    newCoverage,
                    worldPosition:  pos,
                    worldSize:      simd_float3(wall.dimensions.x, wall.dimensions.y, 0.1),
                    worldTransform: wall.transform,
                    topLeftCorner:     corners.topLeft,
                    topRightCorner:    corners.topRight,
                    bottomLeftCorner:  corners.bottomLeft,
                    bottomRightCorner: corners.bottomRight
                )
                coverageDirty = true
            }
        }
        return Array(trackedWalls.values)
    }

    func calculateOverallCoverage() -> Float {
        guard coverageDirty else { return cachedCoverage }
        guard !trackedWalls.isEmpty else { cachedCoverage = 0; coverageDirty = false; return 0 }

        // Single-pass: accumulate total area and covered area simultaneously
        var totalArea: Double = 0
        var coveredArea: Double = 0
        for wall in trackedWalls.values {
            let area = Double(wall.worldSize.x * wall.worldSize.y)
            totalArea   += area
            coveredArea += area * Double(wall.coveragePct)
        }
        cachedCoverage = Float(coveredArea / max(totalArea, 1))
        coverageDirty  = false
        return cachedCoverage
    }

    func reset() {
        trackedWalls.removeAll(keepingCapacity: true)
        insertionCounter = 0
        coverageDirty    = true
        cachedCoverage   = 0
    }

    // MARK: - Private helpers

    private func highlightState(for confidence: CapturedRoom.Confidence) -> TrackedWall.HighlightState {
        switch confidence {
        case .low:    return .partial
        case .medium: return .good
        case .high:   return .complete
        @unknown default: return .none
        }
    }

    private func coveragePercent(for confidence: CapturedRoom.Confidence) -> Float {
        switch confidence {
        case .low:    return 0.25
        case .medium: return 0.65
        case .high:   return 1.0
        @unknown default: return 0.0
        }
    }

    private func extractCorners(wall: CapturedRoom.Wall)
        -> (topLeft: simd_float3, topRight: simd_float3,
            bottomLeft: simd_float3, bottomRight: simd_float3) {
        let w = wall.dimensions.x / 2
        let h = wall.dimensions.y / 2
        let t = wall.transform
        func pt(_ local: simd_float4) -> simd_float3 {
            let w4 = t * local
            return simd_float3(w4.x, w4.y, w4.z)
        }
        return (
            topLeft:     pt(simd_float4(-w,  h, 0, 1)),
            topRight:    pt(simd_float4( w,  h, 0, 1)),
            bottomLeft:  pt(simd_float4(-w, -h, 0, 1)),
            bottomRight: pt(simd_float4( w, -h, 0, 1))
        )
    }
}
