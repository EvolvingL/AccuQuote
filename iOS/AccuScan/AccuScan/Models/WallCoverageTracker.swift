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
            let pos = simd_float3(wall.transform.columns.3.x,
                                  wall.transform.columns.3.y,
                                  wall.transform.columns.3.z)
            let newHighlight = highlightState(for: wall.confidence)
            let newCoverage  = coveragePercent(for: wall.confidence)

            if let existingKey = findExistingKey(near: pos) {
                var existing = trackedWalls[existingKey]!
                // Skip full update if nothing meaningful changed
                guard existing.confidence != wall.confidence else { continue }
                existing.confidence     = wall.confidence
                existing.highlightState = newHighlight
                existing.coveragePct    = newCoverage
                existing.worldPosition  = pos
                existing.worldSize      = simd_float3(wall.dimensions.x, wall.dimensions.y, 0.1)
                existing.worldTransform = wall.transform
                // Only recompute corners when the wall actually moves/resizes
                let corners             = extractCorners(wall: wall)
                existing.topLeftCorner     = corners.topLeft
                existing.topRightCorner    = corners.topRight
                existing.bottomLeftCorner  = corners.bottomLeft
                existing.bottomRightCorner = corners.bottomRight
                trackedWalls[existingKey]  = existing
                coverageDirty = true
            } else {
                insertionCounter += 1
                let newID   = UUID()
                let corners = extractCorners(wall: wall)
                trackedWalls[newID] = TrackedWall(
                    id:             newID,
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

    // O(n) proximity match — n is typically ≤ 12 walls so this is fast in practice.
    // Using a flat array scan avoids the overhead of maintaining a spatial index
    // for such small n.
    private func findExistingKey(near pos: simd_float3) -> UUID? {
        for (key, wall) in trackedWalls
        where simd_distance_squared(wall.worldPosition, pos) < 0.0225 { // 0.15² = 0.0225
            return key
        }
        return nil
    }
}
