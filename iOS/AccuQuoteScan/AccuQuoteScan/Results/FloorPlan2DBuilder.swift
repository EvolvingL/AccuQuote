import Foundation
import RoomPlan
import simd

// MARK: - FloorPlan2DBuilder (Tri-Mode Scanning build spec §5.2)
//
// Projects a captured room into FloorPlan2D's vector primitives — the "many
// renderers, one source of truth" step (§5.1): this is the ONE place a
// CapturedRoom's 3D wall/door/window/object geometry gets turned into 2D
// plan coordinates, so FloorPlan2DView (the renderer) never touches 3D data
// directly and can't disagree with the 3D viewer or the dimension schedule.
//
// Same two-layer split as ScanQualityGate.swift: a pure projection function
// over plain-value samples (fixture-testable — CapturedRoom/Surface/Object
// have no public initializer, so DevToolsChecks can only exercise this
// layer), plus a thin CapturedRoom adapter that's real-scan-only.

enum FloorPlan2DBuilder {

    // MARK: - CapturedRoom extraction (thin adapter, real-scan-only)

    static func build(from room: CapturedRoom, roomName: String) -> FloorPlan2D {
        let wallSamples = room.walls.map(PlanWallSample.init)
        let doorSamples = room.doors.map(PlanOpeningSample.init)
        let windowSamples = room.windows.map(PlanOpeningSample.init)
        let objectSamples = room.objects.map(PlanObjectSample.init)
        return build(walls: wallSamples, doors: doorSamples, windows: windowSamples,
                     objects: objectSamples, roomName: roomName)
    }

    // MARK: - Pure projection (fixture-testable, no RoomPlan types)

    static func build(
        walls: [PlanWallSample],
        doors: [PlanOpeningSample] = [],
        windows: [PlanOpeningSample] = [],
        objects: [PlanObjectSample] = [],
        roomName: String
    ) -> FloorPlan2D {
        let planWalls = walls.map { sample in
            PlanWall(id: sample.id, start: sample.start, end: sample.end,
                      thicknessMetres: sample.thicknessMetres,
                      isEstimatedThickness: sample.isEstimatedThickness,
                      confidence: sample.confidence)
        }

        let planDoors = doors.compactMap { sample -> PlanDoor? in
            guard let wall = nearestWall(to: sample.position, in: walls) else { return nil }
            return doorFromOpening(sample, wall: wall)
        }
        let planWindows = windows.compactMap { sample -> PlanWindow? in
            guard let wall = nearestWall(to: sample.position, in: walls) else { return nil }
            return windowFromOpening(sample, wall: wall)
        }

        // Every wall auto-dimensioned (§5.2), plus two overall bounding
        // dimensions computed from every wall endpoint's bounding box.
        var dimensionStrings = walls.map { dimensionString(for: $0) }
        dimensionStrings += overallBoundingDimensions(walls: walls)

        let roomLabel = roomLabel(name: roomName, walls: walls)

        let symbols = objects.map { obj in
            PlanSymbol(categoryLabel: obj.categoryLabel, position: obj.position,
                       rotationRadians: obj.rotationRadians,
                       widthMetres: obj.widthMetres, depthMetres: obj.depthMetres)
        }

        return FloorPlan2D(
            walls: planWalls, doors: planDoors, windows: planWindows,
            dimensionStrings: dimensionStrings,
            roomLabels: roomLabel.map { [$0] } ?? [],
            symbols: symbols
        )
    }

    // MARK: - Wall association

    /// Doors/windows are positioned near their host wall but rarely exactly
    /// on its centreline — associate by nearest perpendicular distance to
    /// each wall's segment, which is robust to RoomPlan's own small
    /// positional noise between an opening and the wall it interrupts.
    static func nearestWall(to point: SIMD2<Float>, in walls: [PlanWallSample]) -> PlanWallSample? {
        walls.min(by: { distanceToSegment(point, $0.start, $0.end) < distanceToSegment(point, $1.start, $1.end) })
    }

    static func distanceToSegment(_ p: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        let ab = b - a
        let abLenSq = simd_dot(ab, ab)
        guard abLenSq > 0.0001 else { return simd_distance(p, a) }
        let t = max(0, min(1, simd_dot(p - a, ab) / abLenSq))
        let projected = a + ab * t
        return simd_distance(p, projected)
    }

    private static func doorFromOpening(_ sample: PlanOpeningSample, wall: PlanWallSample) -> PlanDoor {
        let halfWidth = sample.widthMetres / 2
        let wallDir = simd_normalize(wall.end - wall.start)
        let hinge = sample.position - wallDir * halfWidth
        let openEnd = sample.position + wallDir * halfWidth
        return PlanDoor(hingePoint: hinge, openEndPoint: openEnd, wallID: wall.id)
    }

    private static func windowFromOpening(_ sample: PlanOpeningSample, wall: PlanWallSample) -> PlanWindow {
        let halfWidth = sample.widthMetres / 2
        let wallDir = simd_normalize(wall.end - wall.start)
        let start = sample.position - wallDir * halfWidth
        let end = sample.position + wallDir * halfWidth
        return PlanWindow(start: start, end: end, wallID: wall.id)
    }

    // MARK: - Dimensioning

    private static func dimensionString(for wall: PlanWallSample) -> PlanDimensionString {
        PlanDimensionString(
            start: wall.start, end: wall.end,
            valueMetres: simd_distance(wall.start, wall.end),
            isOverall: false, associatedWallID: wall.id
        )
    }

    /// Two overall bounding dimensions (§5.2: "overall bounding dimensions on
    /// two sides") — the bounding box's width along X and depth along Y in
    /// plan space, drawn as its own pair of dimension strings independent of
    /// any single wall.
    static func overallBoundingDimensions(walls: [PlanWallSample]) -> [PlanDimensionString] {
        let points = walls.flatMap { [$0.start, $0.end] }
        guard !points.isEmpty else { return [] }
        let xs = points.map { $0.x }, ys = points.map { $0.y }
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return [] }

        let widthDim = PlanDimensionString(
            start: SIMD2(minX, minY), end: SIMD2(maxX, minY),
            valueMetres: maxX - minX, isOverall: true
        )
        let depthDim = PlanDimensionString(
            start: SIMD2(minX, minY), end: SIMD2(minX, maxY),
            valueMetres: maxY - minY, isOverall: true
        )
        return [widthDim, depthDim]
    }

    // MARK: - Room label

    /// Centred in the enclosed region — approximated as the centroid of all
    /// wall endpoints, which is exact for a convex room and a reasonable
    /// approximation for the mildly non-convex rooms RoomPlan typically
    /// produces (true point-in-polygon centroid isn't worth the complexity
    /// here; the label just needs to read as "roughly in the middle").
    static func roomLabel(name: String, walls: [PlanWallSample]) -> PlanRoomLabel? {
        guard !walls.isEmpty else { return nil }
        let points = walls.flatMap { [$0.start, $0.end] }
        let centre = points.reduce(SIMD2<Float>.zero, +) / Float(points.count)
        let area = shoelaceArea(walls: walls)
        return PlanRoomLabel(name: name, floorAreaSqMetres: area, centre: centre)
    }

    /// Shoelace formula over wall endpoints in wall order — an approximation
    /// when walls aren't perfectly ordered head-to-tail (RoomPlan doesn't
    /// guarantee traversal order), but close enough for the label's area
    /// figure; the authoritative floor area still comes from RoomDimensions.
    static func shoelaceArea(walls: [PlanWallSample]) -> Float {
        guard walls.count >= 3 else { return 0 }
        let points = walls.map { $0.start }
        var sum: Float = 0
        for i in 0..<points.count {
            let j = (i + 1) % points.count
            sum += points[i].x * points[j].y - points[j].x * points[i].y
        }
        return abs(sum) / 2
    }
}

// MARK: - Fixture-testable sample types
//
// Plain-value shadows of the RoomPlan data the builder needs — mirrors
// ScanQualityGate.swift's WallSample/OpeningSample pattern exactly. Wall
// start/end are already projected to plan-space XZ-drop (Y dropped, X→X,
// Z→Y) so the pure layer never touches 3D transforms.

struct PlanWallSample {
    let id: String
    let start: SIMD2<Float>
    let end: SIMD2<Float>
    let thicknessMetres: Float
    let isEstimatedThickness: Bool
    let confidence: Float

    init(id: String = UUID().uuidString, start: SIMD2<Float>, end: SIMD2<Float>,
         thicknessMetres: Float = 0.1, isEstimatedThickness: Bool = false, confidence: Float = 1.0) {
        self.id = id
        self.start = start
        self.end = end
        self.thicknessMetres = thicknessMetres
        self.isEstimatedThickness = isEstimatedThickness
        self.confidence = confidence
    }

    /// XZ-drop projection (§5.2 header comment: "simple XZ-drop for Room
    /// mode") — a RoomPlan wall's dimensions.x is its length along its own
    /// local X axis; transforming the two local endpoints (-length/2, 0, 0)
    /// and (+length/2, 0, 0) by the wall's world transform gives world-space
    /// endpoints, then dropping Y (height) projects to plan space.
    init(_ surface: CapturedRoom.Surface) {
        id = surface.identifier.uuidString
        let halfLength = surface.dimensions.x / 2
        let t = surface.transform
        let localStart = SIMD4<Float>(-halfLength, 0, 0, 1)
        let localEnd   = SIMD4<Float>( halfLength, 0, 0, 1)
        let worldStart = t * localStart
        let worldEnd   = t * localEnd
        start = SIMD2(worldStart.x, worldStart.z)
        end   = SIMD2(worldEnd.x, worldEnd.z)
        thicknessMetres = 0.1
        isEstimatedThickness = true   // RoomPlan doesn't report wall thickness — see FloorPlan2DBuilder header
        confidence = PlanWallSample.confidenceValue(surface.confidence)
    }

    private static func confidenceValue(_ c: CapturedRoom.Confidence) -> Float {
        switch c {
        case .low: return 0.3
        case .medium: return 0.65
        case .high: return 1.0
        @unknown default: return 0.65
        }
    }
}

struct PlanOpeningSample {
    let position: SIMD2<Float>
    let widthMetres: Float

    init(position: SIMD2<Float>, widthMetres: Float) {
        self.position = position
        self.widthMetres = widthMetres
    }

    init(_ surface: CapturedRoom.Surface) {
        let t = surface.transform
        position = SIMD2(t.columns.3.x, t.columns.3.z)
        widthMetres = surface.dimensions.x
    }
}

struct PlanObjectSample {
    let categoryLabel: String
    let position: SIMD2<Float>
    let rotationRadians: Float
    let widthMetres: Float
    let depthMetres: Float

    init(categoryLabel: String, position: SIMD2<Float>, rotationRadians: Float, widthMetres: Float, depthMetres: Float) {
        self.categoryLabel = categoryLabel
        self.position = position
        self.rotationRadians = rotationRadians
        self.widthMetres = widthMetres
        self.depthMetres = depthMetres
    }

    init(_ object: CapturedRoom.Object) {
        categoryLabel = PlanObjectSample.label(for: object.category)
        let t = object.transform
        position = SIMD2(t.columns.3.x, t.columns.3.z)
        // Yaw about world Y from the transform's forward column — matches
        // how ScanViewer3D reads camera look direction (columns.2, negated).
        rotationRadians = atan2(t.columns.2.x, t.columns.2.z)
        widthMetres = object.dimensions.x
        depthMetres = object.dimensions.z
    }

    private static func label(for category: CapturedRoom.Object.Category) -> String {
        switch category {
        case .storage:       return "storage"
        case .refrigerator:  return "refrigerator"
        case .stove:         return "stove"
        case .bed:           return "bed"
        case .sink:          return "sink"
        case .washerDryer:   return "washerDryer"
        case .toilet:        return "toilet"
        case .bathtub:       return "bathtub"
        case .oven:          return "oven"
        case .dishwasher:    return "dishwasher"
        case .table:         return "table"
        case .sofa:          return "sofa"
        case .chair:         return "chair"
        case .fireplace:     return "fireplace"
        case .television:    return "television"
        case .stairs:        return "stairs"
        @unknown default:    return "other"
        }
    }
}
