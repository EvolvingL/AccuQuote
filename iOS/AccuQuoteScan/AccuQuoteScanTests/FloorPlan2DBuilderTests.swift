import XCTest
import simd
@testable import AccuQuoteScan

final class FloorPlan2DBuilderTests: XCTestCase {

    /// A simple 4×3m rectangular room fixture, mirroring
    /// DevToolsChecks.fixtureWalls() so the same canonical case is covered
    /// by both the on-device checklist and the automated suite.
    private func fixtureWalls() -> [PlanWallSample] {
        [
            PlanWallSample(id: "north", start: SIMD2(0, 0), end: SIMD2(4, 0)),
            PlanWallSample(id: "east",  start: SIMD2(4, 0), end: SIMD2(4, 3)),
            PlanWallSample(id: "south", start: SIMD2(4, 3), end: SIMD2(0, 3)),
            PlanWallSample(id: "west",  start: SIMD2(0, 3), end: SIMD2(0, 0)),
        ]
    }

    func testBuilderProjectsRectangularRoom() {
        let door = PlanOpeningSample(position: SIMD2(2, 0), widthMetres: 0.9)
        let window = PlanOpeningSample(position: SIMD2(4, 1.5), widthMetres: 1.2)
        let plan = FloorPlan2DBuilder.build(walls: fixtureWalls(), doors: [door], windows: [window], roomName: "Kitchen")

        XCTAssertEqual(plan.walls.count, 4)
        XCTAssertEqual(plan.dimensionStrings.filter { !$0.isOverall }.count, 4)
        XCTAssertEqual(plan.dimensionStrings.filter { $0.isOverall }.count, 2)
        XCTAssertEqual(plan.roomLabels.count, 1)
        XCTAssertEqual(plan.roomLabels[0].floorAreaSqMetres, 12.0, accuracy: 0.1)
        XCTAssertEqual(plan.doors.count, 1)
        XCTAssertEqual(plan.windows.count, 1)
    }

    func testNearestWallAssociatesOpeningCorrectly() {
        let walls = fixtureWalls()
        guard let nearest = FloorPlan2DBuilder.nearestWall(to: SIMD2(2, 0), in: walls) else {
            return XCTFail("nearestWall returned nil")
        }
        XCTAssertEqual(nearest.id, "north")
    }

    func testNearestWallPicksClosestOfMultipleCandidates() {
        let walls = fixtureWalls()
        // (4, 1.5) sits exactly on the east wall's midpoint.
        guard let nearest = FloorPlan2DBuilder.nearestWall(to: SIMD2(4, 1.5), in: walls) else {
            return XCTFail("nearestWall returned nil")
        }
        XCTAssertEqual(nearest.id, "east")
    }

    func testNearestWallReturnsNilForEmptyWalls() {
        XCTAssertNil(FloorPlan2DBuilder.nearestWall(to: SIMD2(0, 0), in: []))
    }

    func testOverallBoundingDimensionsMatchBoundingBox() {
        let walls = fixtureWalls()
        let overall = FloorPlan2DBuilder.overallBoundingDimensions(walls: walls)
        XCTAssertEqual(overall.count, 2)
        XCTAssertTrue(overall.contains { abs($0.valueMetres - 4.0) < 0.01 })
        XCTAssertTrue(overall.contains { abs($0.valueMetres - 3.0) < 0.01 })
    }

    func testOverallBoundingDimensionsEmptyForNoWalls() {
        XCTAssertTrue(FloorPlan2DBuilder.overallBoundingDimensions(walls: []).isEmpty)
    }

    func testDistanceToSegmentPerpendicularCase() {
        // Point directly above the segment midpoint.
        let d = FloorPlan2DBuilder.distanceToSegment(SIMD2(2, 5), SIMD2(0, 0), SIMD2(4, 0))
        XCTAssertEqual(d, 5.0, accuracy: 0.001)
    }

    func testDistanceToSegmentClampsToEndpoint() {
        // Point beyond the segment's end — distance should be to the endpoint,
        // not to the infinite line.
        let d = FloorPlan2DBuilder.distanceToSegment(SIMD2(10, 0), SIMD2(0, 0), SIMD2(4, 0))
        XCTAssertEqual(d, 6.0, accuracy: 0.001)
    }

    func testDistanceToSegmentDegenerateZeroLengthSegment() {
        // start == end: falls back to point-to-point distance rather than
        // dividing by zero (abLenSq guard).
        let d = FloorPlan2DBuilder.distanceToSegment(SIMD2(3, 4), SIMD2(0, 0), SIMD2(0, 0))
        XCTAssertEqual(d, 5.0, accuracy: 0.001)
    }

    func testShoelaceAreaRectangle() {
        let area = FloorPlan2DBuilder.shoelaceArea(walls: fixtureWalls())
        XCTAssertEqual(area, 12.0, accuracy: 0.01)
    }

    func testShoelaceAreaZeroForFewerThanThreeWalls() {
        XCTAssertEqual(FloorPlan2DBuilder.shoelaceArea(walls: Array(fixtureWalls().prefix(2))), 0)
    }

    func testRoomLabelNilForEmptyWalls() {
        XCTAssertNil(FloorPlan2DBuilder.roomLabel(name: "Empty", walls: []))
    }

    func testRoomLabelCentroidIsRoughlyCentred() {
        guard let label = FloorPlan2DBuilder.roomLabel(name: "Kitchen", walls: fixtureWalls()) else {
            return XCTFail("roomLabel returned nil")
        }
        // Centroid of the 8 wall endpoints of a 4x3 rectangle traversed once
        // each direction — should land near (2, 1.5), the true centre.
        XCTAssertEqual(label.centre.x, 2.0, accuracy: 0.5)
        XCTAssertEqual(label.centre.y, 1.5, accuracy: 0.5)
    }

    func testOpeningNotAssociatedWhenNoWallsPresent() {
        let door = PlanOpeningSample(position: SIMD2(2, 0), widthMetres: 0.9)
        let plan = FloorPlan2DBuilder.build(walls: [], doors: [door], roomName: "Empty")
        XCTAssertTrue(plan.doors.isEmpty, "a door can't be associated with a wall when there are no walls")
    }

    // MARK: - Symbols (objects)

    func testObjectsProjectToSymbols() {
        let obj = PlanObjectSample(categoryLabel: "sink", position: SIMD2(1, 1), rotationRadians: 0, widthMetres: 0.6, depthMetres: 0.5)
        let plan = FloorPlan2DBuilder.build(walls: fixtureWalls(), objects: [obj], roomName: "Kitchen")
        XCTAssertEqual(plan.symbols.count, 1)
        XCTAssertEqual(plan.symbols[0].categoryLabel, "sink")
    }

    // MARK: - Stress: many walls (Full Works multi-room scale)

    func testBuilderHandlesLargeNumberOfWallsWithinBoundedTime() {
        // Simulates a large multi-room Full Works floor: 200 rooms worth of
        // walls (4 each = 800 walls), each offset so they don't overlap.
        var walls: [PlanWallSample] = []
        for room in 0..<200 {
            let ox = Float(room % 20) * 5
            let oy = Float(room / 20) * 5
            walls.append(PlanWallSample(id: "r\(room)-n", start: SIMD2(ox, oy), end: SIMD2(ox + 4, oy)))
            walls.append(PlanWallSample(id: "r\(room)-e", start: SIMD2(ox + 4, oy), end: SIMD2(ox + 4, oy + 3)))
            walls.append(PlanWallSample(id: "r\(room)-s", start: SIMD2(ox + 4, oy + 3), end: SIMD2(ox, oy + 3)))
            walls.append(PlanWallSample(id: "r\(room)-w", start: SIMD2(ox, oy + 3), end: SIMD2(ox, oy)))
        }

        let start = Date()
        let plan = FloorPlan2DBuilder.build(walls: walls, roomName: "Whole House")
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(plan.walls.count, 800)
        XCTAssertLessThan(elapsed, 5.0, "building an 800-wall plan took \(elapsed)s")
    }
}
