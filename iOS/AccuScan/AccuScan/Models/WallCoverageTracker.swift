import RoomPlan
import simd

// MARK: - TrackedWall

struct TrackedWall: Identifiable {
    let id: UUID
    let insertionOrder: Int          // stable detection order for sorting wall tiles
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
        case none
        case partial
        case good
        case complete
    }
}

// MARK: - WallCoverageTracker
// @MainActor: all access is serialised through the main actor so the compiler
// enforces that no background thread reads or writes the tracked state.

@MainActor
final class WallCoverageTracker {

    private var trackedWalls: [UUID: TrackedWall] = [:]
    private var insertionCounter = 0

    func update(from room: CapturedRoom) -> [TrackedWall] {
        for wall in room.walls {
            let existingKey = findExisting(wall: wall)

            if let key = existingKey {
                // Update existing wall — preserve insertionOrder and id
                let corners = extractCorners(wall: wall)
                var existing = trackedWalls[key]!
                existing = TrackedWall(
                    id:             existing.id,
                    insertionOrder: existing.insertionOrder,
                    roomPlanWall:   wall,
                    confidence:     wall.confidence,
                    highlightState: highlightState(for: wall.confidence),
                    coveragePct:    coveragePercent(for: wall.confidence),
                    worldPosition:  simd_float3(wall.transform.columns.3.x,
                                                wall.transform.columns.3.y,
                                                wall.transform.columns.3.z),
                    worldSize:      simd_float3(wall.dimensions.x, wall.dimensions.y, 0.1),
                    worldTransform: wall.transform,
                    topLeftCorner:     corners.topLeft,
                    topRightCorner:    corners.topRight,
                    bottomLeftCorner:  corners.bottomLeft,
                    bottomRightCorner: corners.bottomRight
                )
                trackedWalls[key] = existing
            } else {
                // New wall — assign a stable id and insertion order
                let newID = UUID()
                insertionCounter += 1
                let corners = extractCorners(wall: wall)
                trackedWalls[newID] = TrackedWall(
                    id:             newID,
                    insertionOrder: insertionCounter,
                    roomPlanWall:   wall,
                    confidence:     wall.confidence,
                    highlightState: highlightState(for: wall.confidence),
                    coveragePct:    coveragePercent(for: wall.confidence),
                    worldPosition:  simd_float3(wall.transform.columns.3.x,
                                                wall.transform.columns.3.y,
                                                wall.transform.columns.3.z),
                    worldSize:      simd_float3(wall.dimensions.x, wall.dimensions.y, 0.1),
                    worldTransform: wall.transform,
                    topLeftCorner:     corners.topLeft,
                    topRightCorner:    corners.topRight,
                    bottomLeftCorner:  corners.bottomLeft,
                    bottomRightCorner: corners.bottomRight
                )
            }
        }
        return Array(trackedWalls.values)
    }

    func calculateOverallCoverage() -> Float {
        guard !trackedWalls.isEmpty else { return 0 }
        let totalArea   = trackedWalls.values.reduce(0.0) { $0 + Double($1.worldSize.x * $1.worldSize.y) }
        let coveredArea = trackedWalls.values.reduce(0.0) { $0 + Double($1.worldSize.x * $1.worldSize.y) * Double($1.coveragePct) }
        return Float(coveredArea / max(totalArea, 1))
    }

    func reset() {
        trackedWalls.removeAll()
        insertionCounter = 0
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

    private func extractCorners(wall: CapturedRoom.Wall) -> (topLeft: simd_float3, topRight: simd_float3, bottomLeft: simd_float3, bottomRight: simd_float3) {
        let w = wall.dimensions.x / 2
        let h = wall.dimensions.y / 2
        let t = wall.transform

        func pt(_ local: simd_float4) -> simd_float3 {
            let w4 = t * local; return simd_float3(w4.x, w4.y, w4.z)
        }

        return (
            topLeft:     pt(simd_float4(-w,  h, 0, 1)),
            topRight:    pt(simd_float4( w,  h, 0, 1)),
            bottomLeft:  pt(simd_float4(-w, -h, 0, 1)),
            bottomRight: pt(simd_float4( w, -h, 0, 1))
        )
    }

    private func findExisting(wall: CapturedRoom.Wall) -> UUID? {
        let pos = simd_float3(wall.transform.columns.3.x,
                              wall.transform.columns.3.y,
                              wall.transform.columns.3.z)
        return trackedWalls.first { simd_distance($1.worldPosition, pos) < 0.15 }?.key
    }
}
