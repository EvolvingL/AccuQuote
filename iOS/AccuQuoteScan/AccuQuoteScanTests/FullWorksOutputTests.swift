import XCTest
@testable import AccuQuoteScan

// FullWorksOutput is @available(iOS 17.0, *) — every test guards with
// #available and skips (rather than fails) below iOS 17, matching
// DevToolsChecks' own convention for this type. The simulator runtime this
// suite targets is iOS 17+ in practice, so these should actually execute,
// not just skip.
final class FullWorksOutputTests: XCTestCase {

    func testCSVEscapesSpecialCharacters() throws {
        guard #available(iOS 17.0, *) else {
            throw XCTSkip("FullWorksOutput requires iOS 17+")
        }
        XCTAssertEqual(FullWorksOutput.csvField("Kitchen"), "Kitchen")
        XCTAssertEqual(FullWorksOutput.csvField("Kitchen, Utility"), "\"Kitchen, Utility\"")
        XCTAssertEqual(FullWorksOutput.csvField("12\" void"), "\"12\"\" void\"")
    }

    func testCSVFieldWithNewlineIsQuoted() throws {
        guard #available(iOS 17.0, *) else {
            throw XCTSkip("FullWorksOutput requires iOS 17+")
        }
        XCTAssertEqual(FullWorksOutput.csvField("Line1\nLine2"), "\"Line1\nLine2\"")
    }

    func testCSVRoundTripsDimensionSchedule() throws {
        guard #available(iOS 17.0, *) else {
            throw XCTSkip("FullWorksOutput requires iOS 17+")
        }
        let schedule = [
            RoomDimensionRecord(roomName: "Kitchen", length: 4.2, width: 3.1, height: 2.4,
                                 floorArea: 13.02, wallArea: 35.04, doorCount: 1, windowCount: 2),
            RoomDimensionRecord(roomName: "Lounge, Diner", length: 5.0, width: 4.0, height: 2.4,
                                 floorArea: 20.0, wallArea: 43.2, doorCount: 2, windowCount: 3),
        ]
        let csv = FullWorksOutput.csvString(for: schedule)
        let lines = csv.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0], "Room,Length (m),Width (m),Height (m),Floor Area (m²),Wall Area (m²),Doors,Windows")
        XCTAssertEqual(lines[1], "Kitchen,4.20,3.10,2.40,13.02,35.04,1,2")
        XCTAssertEqual(lines[2], "\"Lounge, Diner\",5.00,4.00,2.40,20.00,43.20,2,3")
    }

    func testCSVStringForEmptySchedule() throws {
        guard #available(iOS 17.0, *) else {
            throw XCTSkip("FullWorksOutput requires iOS 17+")
        }
        let csv = FullWorksOutput.csvString(for: [])
        XCTAssertEqual(csv.components(separatedBy: "\n").count, 1, "header line only")
    }

    // MARK: - Stress: large dimension schedule (whole-house Full Works scan)

    func testCSVGenerationForLargeScheduleWithinBoundedTime() throws {
        guard #available(iOS 17.0, *) else {
            throw XCTSkip("FullWorksOutput requires iOS 17+")
        }
        let schedule = (0..<500).map { i in
            RoomDimensionRecord(roomName: "Room, \(i)", length: 4.0, width: 3.0, height: 2.4,
                                 floorArea: 12.0, wallArea: 33.6, doorCount: 1, windowCount: 2)
        }
        let start = Date()
        let csv = FullWorksOutput.csvString(for: schedule)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(csv.components(separatedBy: "\n").count, 501)
        XCTAssertLessThan(elapsed, 2.0, "CSV generation for 500 rooms took \(elapsed)s")
    }
}
