import XCTest
import simd
@testable import AccuQuoteScan

final class ScanResultCodableTests: XCTestCase {

    func testScanResultRoundTrip() throws {
        let original = ScanResult(
            mode: .room,
            surfaces: [Surface(category: .wall, polygon: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(1, 0, 1)], confidence: 0.9)],
            dimensionSchedule: [RoomDimensionRecord(roomName: "Kitchen", length: 4.2, width: 3.1, height: 2.4,
                                                     floorArea: 13.02, wallArea: 35.04, doorCount: 1, windowCount: 2)]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ScanResult.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.mode, original.mode)
        XCTAssertEqual(decoded.surfaces.count, 1)
        XCTAssertEqual(decoded.dimensionSchedule.first?.roomName, "Kitchen")
    }

    func testScanResultBackwardsCompatibleDecodeFromOldShape() throws {
        let oldShapeJSON = """
        {"id":"abc-123","mode":"room","capturedAt":\(Date().timeIntervalSinceReferenceDate)}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ScanResult.self, from: oldShapeJSON)
        XCTAssertTrue(decoded.surfaces.isEmpty)
        XCTAssertTrue(decoded.dimensionSchedule.isEmpty)
        XCTAssertEqual(decoded.confidence.overallScore, 1.0)
        XCTAssertTrue(decoded.confidence.isPassing)
        XCTAssertTrue(decoded.floorPlan2D.walls.isEmpty)
    }

    func testScanResultDecodeThrowsOnMissingRequiredFields() {
        // `id`/`mode`/`capturedAt` are NOT optional-decoded — missing them
        // must throw, not silently default, since there's no sane fallback
        // for "which scan is this."
        let brokenJSON = "{}".data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(ScanResult.self, from: brokenJSON))
    }

    func testScanConfidenceBackwardsCompatibleDecode() throws {
        let emptyJSON = "{}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ScanConfidence.self, from: emptyJSON)
        XCTAssertEqual(decoded.overallScore, 1.0)
        XCTAssertTrue(decoded.issues.isEmpty)
        XCTAssertTrue(decoded.isPassing)
    }

    func testScanConfidenceIsPassingRequiresNoBlockingIssueRegardlessOfScore() {
        let issue = ScanIssue(kind: .openLoop, severity: .blocking, worldAnchor: .zero, affectedSurfaceIDs: ["w"], hint: "")
        let confidence = ScanConfidence(overallScore: 1.0, issues: [issue])
        XCTAssertFalse(confidence.isPassing, "a perfect score with a blocking issue must still fail")
    }

    func testScanConfidenceIsPassingFailsBelowThresholdEvenWithNoIssues() {
        let confidence = ScanConfidence(overallScore: 0.5, issues: [])
        XCTAssertFalse(confidence.isPassing)
    }

    func testFloorPlan2DBackwardsCompatibleDecodeFromEmptyJSON() throws {
        let decoded = try JSONDecoder().decode(FloorPlan2D.self, from: "{}".data(using: .utf8)!)
        XCTAssertTrue(decoded.walls.isEmpty)
        XCTAssertTrue(decoded.doors.isEmpty)
        XCTAssertEqual(decoded.scaleBarMetres, 1.0)
        XCTAssertNil(decoded.northAngleRadians)
    }

    func testFloorPlan2DRoundTrip() throws {
        let plan = FloorPlan2D(
            walls: [PlanWall(start: SIMD2(0, 0), end: SIMD2(4, 0))],
            doors: [PlanDoor(hingePoint: SIMD2(1, 0), openEndPoint: SIMD2(2, 0), wallID: "w0")],
            windows: [],
            dimensionStrings: [PlanDimensionString(start: .zero, end: SIMD2(4, 0), valueMetres: 4.0)],
            roomLabels: [PlanRoomLabel(name: "Kitchen", floorAreaSqMetres: 12, centre: SIMD2(2, 1.5))],
            symbols: []
        )
        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(FloorPlan2D.self, from: data)
        XCTAssertEqual(decoded.walls.count, 1)
        XCTAssertEqual(decoded.doors.first?.wallID, "w0")
        XCTAssertEqual(decoded.roomLabels.first?.name, "Kitchen")
    }

    // MARK: - SavedQuote / QuoteHistory model

    func testSavedQuoteDecodesOldJSONWithSafeDefaults() throws {
        let oldShapeJSON = """
        {"id":"abc-123","savedAt":\(Date().timeIntervalSinceReferenceDate),
         "customerName":"Mr Smith","jobDescription":"Rewire","roomType":"bedroom",
         "floorArea":12.5,"labourDays":2,"labourRate":280,"labourTotal":560,
         "items":[],"subtotal":560,"vatRate":20,"vatAmount":112,"grandTotal":672,
         "notes":"","sections":[]}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(SavedQuote.self, from: oldShapeJSON)
        XCTAssertEqual(decoded.scanMode, "room")
        XCTAssertNil(decoded.scanArtifactURL)
        XCTAssertNil(decoded.thumbnailURL)
    }

    func testSavedQuoteThumbnailURLDerivesFromArtifactURL() {
        let quote = SavedQuote(
            id: "x", savedAt: Date(), customerName: "", jobDescription: "", roomType: "bedroom",
            floorArea: 10, labourDays: 1, labourRate: 280, labourTotal: 280, items: [],
            subtotal: 280, vatRate: 20, vatAmount: 56, grandTotal: 336, notes: "",
            scanMode: "space", scanArtifactURL: "file:///Documents/aq_scans/abc/model.usdz"
        )
        XCTAssertEqual(quote.thumbnailURL?.absoluteString, "file:///Documents/aq_scans/abc/thumb.jpg")
        XCTAssertEqual(quote.scanModeDisplayLabel, "Space")
    }

    func testSavedQuoteScanModeDisplayLabels() {
        func quote(scanMode: String) -> SavedQuote {
            SavedQuote(id: "x", savedAt: Date(), customerName: "", jobDescription: "", roomType: "bedroom",
                       floorArea: 1, labourDays: 0, labourRate: 0, labourTotal: 0, items: [],
                       subtotal: 0, vatRate: 20, vatAmount: 0, grandTotal: 0, notes: "", scanMode: scanMode)
        }
        XCTAssertEqual(quote(scanMode: "room").scanModeDisplayLabel, "Room")
        XCTAssertEqual(quote(scanMode: "space").scanModeDisplayLabel, "Space")
        XCTAssertEqual(quote(scanMode: "fullWorks").scanModeDisplayLabel, "Full Works")
        XCTAssertEqual(quote(scanMode: "unknown-future-mode").scanModeDisplayLabel, "Room", "unrecognised scanMode should default safely, not crash")
    }

    func testSavedQuoteItemDecodesOldJSONWithoutSectionKey() throws {
        let json = """
        {"id":"i1","description":"Socket","qty":2,"unit":"each","unitPrice":15.5,"sku":"S1","supplier":"Screwfix"}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SavedQuoteItem.self, from: json)
        XCTAssertEqual(decoded.sectionKey, "")
        XCTAssertEqual(decoded.total, 31.0, accuracy: 0.001)
    }

    func testSavedQuoteRoundTrip() throws {
        let item = SavedQuoteItem(id: "i1", description: "Socket", qty: 2, unit: "each", unitPrice: 15.5, sku: "S1", supplier: "Screwfix")
        let quote = SavedQuote(
            id: "q1", savedAt: Date(), customerName: "Jane", jobDescription: "Rewire kitchen",
            roomType: "kitchen", floorArea: 12.5, labourDays: 2, labourRate: 280, labourTotal: 560,
            items: [item], subtotal: 591, vatRate: 20, vatAmount: 118.2, grandTotal: 709.2, notes: "Note"
        )
        let data = try JSONEncoder().encode(quote)
        let decoded = try JSONDecoder().decode(SavedQuote.self, from: data)
        XCTAssertEqual(decoded.id, quote.id)
        XCTAssertEqual(decoded.items.count, 1)
        XCTAssertEqual(decoded.grandTotal, 709.2, accuracy: 0.001)
    }

    // MARK: - Surface / DetectedObject Codable

    func testSurfaceRoundTripPreservesPolygonAndEdges() throws {
        let surface = Surface(
            category: .wall,
            polygon: [SIMD3(0, 0, 0), SIMD3(1, 0, 0)],
            confidence: 0.75,
            edges: [Edge(startIndex: 0, endIndex: 1, adjacentSurfaceID: "neighbour")]
        )
        let data = try JSONEncoder().encode(surface)
        let decoded = try JSONDecoder().decode(Surface.self, from: data)
        XCTAssertEqual(decoded.polygon.count, 2)
        XCTAssertEqual(decoded.edges.first?.adjacentSurfaceID, "neighbour")
    }

    func testDetectedObjectRoundTrip() throws {
        let object = DetectedObject(categoryLabel: "sink", transform: Array(repeating: 0, count: 16), dimensions: SIMD3(0.6, 0.5, 0.4), confidence: 0.8)
        let data = try JSONEncoder().encode(object)
        let decoded = try JSONDecoder().decode(DetectedObject.self, from: data)
        XCTAssertEqual(decoded.categoryLabel, "sink")
        XCTAssertEqual(decoded.transform.count, 16)
    }
}
