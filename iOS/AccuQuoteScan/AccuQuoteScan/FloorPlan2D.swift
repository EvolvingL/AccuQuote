import Foundation
import simd

// MARK: - FloorPlan2D (Tri-Mode Scanning build spec §5.2)
//
// Resolved vector primitives for the architectural 2D floor plan — walls,
// door swings, window lines, dimension strings, room labels, fixture symbols.
// Holding these as data (not pixels) is what makes the plan reproducible,
// diff-able, and re-renderable: a future renderer can re-emit a prettier plan
// from old FloorPlan2D data without re-scanning (§5.5's "do not treat the
// rendered PDF as the source of truth").
//
// Coordinates are in the plan's own 2D projection space (metres, top-down),
// separate from the 3D world-space coordinates in Surface/DetectedObject —
// the projection (e.g. dominant-plane fit, or simple XZ-drop for Room mode)
// is computed once when the plan is generated and cached here, not
// recomputed on every render.

struct FloorPlan2D: Codable {
    var walls: [PlanWall]
    var doors: [PlanDoor]
    var windows: [PlanWindow]
    var dimensionStrings: [PlanDimensionString]
    var roomLabels: [PlanRoomLabel]
    var symbols: [PlanSymbol]
    var northAngleRadians: Float?   // captured via CMMotionManager at scan start; nil if unavailable
    var scaleBarMetres: Float = 1.0

    init(walls: [PlanWall], doors: [PlanDoor], windows: [PlanWindow],
         dimensionStrings: [PlanDimensionString], roomLabels: [PlanRoomLabel],
         symbols: [PlanSymbol], northAngleRadians: Float? = nil, scaleBarMetres: Float = 1.0) {
        self.walls = walls
        self.doors = doors
        self.windows = windows
        self.dimensionStrings = dimensionStrings
        self.roomLabels = roomLabels
        self.symbols = symbols
        self.northAngleRadians = northAngleRadians
        self.scaleBarMetres = scaleBarMetres
    }

    // Backwards-compatible decode — a ScanResult saved before the 2D plan
    // pipeline existed has no plan data; render callers must handle an
    // all-empty FloorPlan2D (no walls to draw) rather than crash.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        walls = (try? c.decode([PlanWall].self, forKey: .walls)) ?? []
        doors = (try? c.decode([PlanDoor].self, forKey: .doors)) ?? []
        windows = (try? c.decode([PlanWindow].self, forKey: .windows)) ?? []
        dimensionStrings = (try? c.decode([PlanDimensionString].self, forKey: .dimensionStrings)) ?? []
        roomLabels = (try? c.decode([PlanRoomLabel].self, forKey: .roomLabels)) ?? []
        symbols = (try? c.decode([PlanSymbol].self, forKey: .symbols)) ?? []
        northAngleRadians = try? c.decode(Float.self, forKey: .northAngleRadians)
        scaleBarMetres = (try? c.decode(Float.self, forKey: .scaleBarMetres)) ?? 1.0
    }
}

// MARK: - PlanWall
//
// Double-line stroke with thickness (§5.2 rendering rules). thicknessMetres
// comes from RoomPlan when available; isEstimatedThickness flags the
// 100mm-default fallback so the renderer can draw the hairline dashed inner
// line the spec calls for.

struct PlanWall: Codable, Identifiable {
    let id: String
    var start: SIMD2<Float>
    var end: SIMD2<Float>
    var thicknessMetres: Float
    var isEstimatedThickness: Bool
    var confidence: Float

    init(id: String = UUID().uuidString, start: SIMD2<Float>, end: SIMD2<Float>,
         thicknessMetres: Float = 0.1, isEstimatedThickness: Bool = false, confidence: Float = 1.0) {
        self.id = id
        self.start = start
        self.end = end
        self.thicknessMetres = thicknessMetres
        self.isEstimatedThickness = isEstimatedThickness
        self.confidence = confidence
    }
}

// MARK: - PlanDoor
//
// Opening gap in the wall + quarter-circle swing arc.

struct PlanDoor: Codable, Identifiable {
    let id: String
    var hingePoint: SIMD2<Float>
    var openEndPoint: SIMD2<Float>   // far end of the door leaf when closed
    var swingRadians: Float          // arc sweep, typically .pi / 2
    var wallID: String               // which PlanWall this opening interrupts

    init(id: String = UUID().uuidString, hingePoint: SIMD2<Float>, openEndPoint: SIMD2<Float>,
         swingRadians: Float = .pi / 2, wallID: String) {
        self.id = id
        self.hingePoint = hingePoint
        self.openEndPoint = openEndPoint
        self.swingRadians = swingRadians
        self.wallID = wallID
    }
}

// MARK: - PlanWindow
//
// Triple parallel line across the opening.

struct PlanWindow: Codable, Identifiable {
    let id: String
    var start: SIMD2<Float>
    var end: SIMD2<Float>
    var wallID: String

    init(id: String = UUID().uuidString, start: SIMD2<Float>, end: SIMD2<Float>, wallID: String) {
        self.id = id
        self.start = start
        self.end = end
        self.wallID = wallID
    }
}

// MARK: - PlanDimensionString
//
// Extension + dimension lines with ticks, drawn outside the wall line.
// Every wall is auto-dimensioned; overall bounding dimensions are two
// additional strings with isOverall = true.

struct PlanDimensionString: Codable, Identifiable {
    let id: String
    var start: SIMD2<Float>
    var end: SIMD2<Float>
    var valueMetres: Float
    var isOverall: Bool
    var associatedWallID: String?   // nil for overall bounding dimensions

    init(id: String = UUID().uuidString, start: SIMD2<Float>, end: SIMD2<Float>,
         valueMetres: Float, isOverall: Bool = false, associatedWallID: String? = nil) {
        self.id = id
        self.start = start
        self.end = end
        self.valueMetres = valueMetres
        self.isOverall = isOverall
        self.associatedWallID = associatedWallID
    }
}

// MARK: - PlanRoomLabel

struct PlanRoomLabel: Codable, Identifiable {
    let id: String
    var name: String
    var floorAreaSqMetres: Float
    var centre: SIMD2<Float>   // centred in the enclosed region

    init(id: String = UUID().uuidString, name: String, floorAreaSqMetres: Float, centre: SIMD2<Float>) {
        self.id = id
        self.name = name
        self.floorAreaSqMetres = floorAreaSqMetres
        self.centre = centre
    }
}

// MARK: - PlanSymbol
//
// Standardised architectural symbol keyed to a RoomPlan object category
// (sink, toilet, bath, cabinet, …). Unknown categories fall back to a
// labelled rectangle at render time rather than failing to draw.

struct PlanSymbol: Codable, Identifiable {
    let id: String
    var categoryLabel: String   // matches DetectedObject.categoryLabel
    var position: SIMD2<Float>
    var rotationRadians: Float
    var widthMetres: Float
    var depthMetres: Float

    init(id: String = UUID().uuidString, categoryLabel: String, position: SIMD2<Float>,
         rotationRadians: Float, widthMetres: Float, depthMetres: Float) {
        self.id = id
        self.categoryLabel = categoryLabel
        self.position = position
        self.rotationRadians = rotationRadians
        self.widthMetres = widthMetres
        self.depthMetres = depthMetres
    }
}
