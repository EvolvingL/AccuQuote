import Foundation
import simd

// MARK: - ScanResult (canonical multi-mode geometry model)
//
// Tri-Mode Scanning build spec §5.1. Every scan mode (Room/Space/Full Works),
// on completion, produces exactly one ScanResult — the single object every
// output (2D plan, 3D model, dimension CSV) derives from. One source of truth,
// many renderers: a value changed on one output must appear identically on
// the others because they all read from this, never from independent
// per-renderer calculations.
//
// This model is additive and stands alongside the existing RoomDimensions/
// ScanState/ScanMethod types in ScanCoordinator.swift — it does not replace
// them. Room mode keeps producing RoomDimensions for the existing UI in
// parallel with a ScanResult for the new pipeline until the phased rollout
// (see build plan) retires the old path.
//
// Field names/shapes here are kept identical to the sibling type in AccuScan's
// Models/ so a scan taken in either app is structurally interchangeable JSON.

struct ScanResult: Codable, Identifiable {
    let id: String
    let mode: ScanMode
    let capturedAt: Date

    // Canonical geometry (world space, metres, +Y up, right-handed)
    var surfaces: [Surface]
    var objects: [DetectedObject]
    var meshURL: URL?          // high-res triangle mesh (USDZ) for 3D + export
    var pointCloudURL: URL?    // raw points (Space mode / QA only)

    // Derived + cached at save time (never recomputed at display time)
    var dimensionSchedule: [RoomDimensionRecord]
    var confidence: ScanConfidence
    var floorPlan2D: FloorPlan2D
    var thumbnailURL: URL?     // pre-rendered 3D snapshot JPEG

    init(
        id: String = UUID().uuidString,
        mode: ScanMode,
        capturedAt: Date = Date(),
        surfaces: [Surface] = [],
        objects: [DetectedObject] = [],
        meshURL: URL? = nil,
        pointCloudURL: URL? = nil,
        dimensionSchedule: [RoomDimensionRecord] = [],
        confidence: ScanConfidence = ScanConfidence(overallScore: 1.0, issues: []),
        floorPlan2D: FloorPlan2D = FloorPlan2D(walls: [], doors: [], windows: [], dimensionStrings: [], roomLabels: [], symbols: []),
        thumbnailURL: URL? = nil
    ) {
        self.id = id
        self.mode = mode
        self.capturedAt = capturedAt
        self.surfaces = surfaces
        self.objects = objects
        self.meshURL = meshURL
        self.pointCloudURL = pointCloudURL
        self.dimensionSchedule = dimensionSchedule
        self.confidence = confidence
        self.floorPlan2D = floorPlan2D
        self.thumbnailURL = thumbnailURL
    }

    // Backwards-compatible decode — every field added after initial ship
    // defaults via (try? …) ?? default, matching the convention already used
    // in QuoteHistory.swift (SavedQuote/SavedQuoteItem) so old on-disk records
    // keep opening after this feature ships.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        mode = try c.decode(ScanMode.self, forKey: .mode)
        capturedAt = try c.decode(Date.self, forKey: .capturedAt)
        surfaces = (try? c.decode([Surface].self, forKey: .surfaces)) ?? []
        objects = (try? c.decode([DetectedObject].self, forKey: .objects)) ?? []
        meshURL = try? c.decode(URL.self, forKey: .meshURL)
        pointCloudURL = try? c.decode(URL.self, forKey: .pointCloudURL)
        dimensionSchedule = (try? c.decode([RoomDimensionRecord].self, forKey: .dimensionSchedule)) ?? []
        confidence = (try? c.decode(ScanConfidence.self, forKey: .confidence)) ?? ScanConfidence(overallScore: 1.0, issues: [])
        floorPlan2D = (try? c.decode(FloorPlan2D.self, forKey: .floorPlan2D))
            ?? FloorPlan2D(walls: [], doors: [], windows: [], dimensionStrings: [], roomLabels: [], symbols: [])
        thumbnailURL = try? c.decode(URL.self, forKey: .thumbnailURL)
    }
}

// MARK: - ScanMode
//
// What is being scanned — distinct from ScanMethod (how it's scanned:
// lidar/poseFusion/manual), which already exists in ScanCoordinator.swift.

enum ScanMode: String, Codable {
    case room
    case space
    case fullWorks
}

// MARK: - Surface

enum SurfaceCategory: String, Codable {
    case wall
    case floor
    case ceiling
    case openingDoor
    case openingWindow
}

struct Edge: Codable {
    var startIndex: Int   // index into the owning Surface.polygon
    var endIndex: Int
    var adjacentSurfaceID: String?   // nil = boundary edge (no neighbour) — used by the
                                       // quality gate's open-loop detection (§5.4)
}

struct Surface: Codable, Identifiable {
    let id: String
    let category: SurfaceCategory
    var polygon: [SIMD3<Float>]   // ordered boundary loop, world space
    var confidence: Float         // 0…1, from RoomPlan/ARKit confidence
    var edges: [Edge]

    init(id: String = UUID().uuidString, category: SurfaceCategory, polygon: [SIMD3<Float>], confidence: Float, edges: [Edge] = []) {
        self.id = id
        self.category = category
        self.polygon = polygon
        self.confidence = confidence
        self.edges = edges
    }
}

// MARK: - DetectedObject
//
// RoomPlan object categories (sink, toilet, window, door, cabinet, …) plus
// bounding geometry, used by the 2D plan's fixture-symbol renderer (§5.2) and
// the 3D viewer's per-category colouring.

struct DetectedObject: Codable, Identifiable {
    let id: String
    let categoryLabel: String   // e.g. "sink", "toilet" — free-form so unknown
                                 // RoomPlan categories degrade to a labelled
                                 // rectangle rather than crashing a switch.
    var transform: [Float]      // flattened 4x4, world space
    var dimensions: SIMD3<Float>
    var confidence: Float

    init(id: String = UUID().uuidString, categoryLabel: String, transform: [Float], dimensions: SIMD3<Float>, confidence: Float) {
        self.id = id
        self.categoryLabel = categoryLabel
        self.transform = transform
        self.dimensions = dimensions
        self.confidence = confidence
    }
}

// MARK: - RoomDimensionRecord
//
// One row of the Full Works dimension schedule (§4.2) / dimension CSV (§5.5).
// A ScanResult with mode == .room has exactly one record; .fullWorks has one
// per room.

struct RoomDimensionRecord: Codable, Identifiable {
    let id: String
    var roomName: String
    var length: Double
    var width: Double
    var height: Double
    var floorArea: Double
    var wallArea: Double
    var doorCount: Int
    var windowCount: Int

    init(id: String = UUID().uuidString, roomName: String, length: Double, width: Double, height: Double,
         floorArea: Double, wallArea: Double, doorCount: Int, windowCount: Int) {
        self.id = id
        self.roomName = roomName
        self.length = length
        self.width = width
        self.height = height
        self.floorArea = floorArea
        self.wallArea = wallArea
        self.doorCount = doorCount
        self.windowCount = windowCount
    }
}
