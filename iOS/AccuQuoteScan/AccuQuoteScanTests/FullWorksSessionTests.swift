import XCTest
@testable import AccuQuoteScan

// MARK: - FullWorksSessionTests
//
// FullWorksSession's real per-room work (recordCompletedRoom, merge()) needs
// a genuine CapturedRoom, which — like everywhere else in this codebase —
// has no public initializer and can only come from a real RoomPlan scan.
// What IS testable here is the surrounding state-machine/setup logic that
// operates on empty/plain-value Floor state: start(), addFloor(), the
// finishFloor() phase transition, and the stat helpers.

@MainActor
final class FullWorksSessionTests: XCTestCase {

    func testStartInitialisesSingleFloor() {
        let session = FullWorksSession()
        session.start(propertyName: "12 High Street", firstFloorLabel: "Ground Floor")
        XCTAssertEqual(session.propertyName, "12 High Street")
        XCTAssertEqual(session.floors.count, 1)
        XCTAssertEqual(session.floors.first?.label, "Ground Floor")
        XCTAssertEqual(session.currentFloorIndex, 0)
        if case .setup = session.phase {} else { XCTFail("expected .setup phase") }
    }

    func testAddFloorAppendsAndSelectsNewFloor() {
        let session = FullWorksSession()
        session.start(propertyName: "Test House", firstFloorLabel: "Ground Floor")
        session.addFloor(label: "First Floor")
        XCTAssertEqual(session.floors.count, 2)
        XCTAssertEqual(session.currentFloorIndex, 1)
        XCTAssertEqual(session.currentFloor?.label, "First Floor")
        if case .betweenRooms = session.phase {} else { XCTFail("expected .betweenRooms phase") }
    }

    func testCurrentFloorNilWhenIndexOutOfRange() {
        let session = FullWorksSession()
        // Never started — floors is empty, currentFloorIndex is 0.
        XCTAssertNil(session.currentFloor)
    }

    func testTotalRoomCountAndFloorAreaAreZeroForEmptyFloors() {
        let session = FullWorksSession()
        session.start(propertyName: "Empty House", firstFloorLabel: "Ground Floor")
        XCTAssertEqual(session.totalRoomCount, 0)
        XCTAssertEqual(session.totalFloorAreaSqMetres, 0)
    }

    func testResetReturnsToSetupPhaseAndClearsState() {
        let session = FullWorksSession()
        session.start(propertyName: "Test House", firstFloorLabel: "Ground Floor")
        session.addFloor(label: "First Floor")
        session.reset()
        XCTAssertEqual(session.propertyName, "")
        XCTAssertTrue(session.floors.isEmpty)
        XCTAssertEqual(session.currentFloorIndex, 0)
        if case .setup = session.phase {} else { XCTFail("expected .setup phase after reset") }
    }

    func testBeginScanningNextRoomSetsPhase() {
        let session = FullWorksSession()
        session.start(propertyName: "Test House", firstFloorLabel: "Ground Floor")
        session.beginScanningNextRoom()
        if case .scanningRoom = session.phase {} else { XCTFail("expected .scanningRoom phase") }
    }

    func testScanDurationDescriptionNilBeforeStart() {
        let session = FullWorksSession()
        XCTAssertNil(session.scanDurationDescription)
    }

    func testScanDurationDescriptionReportsUnderAMinuteImmediatelyAfterStart() {
        let session = FullWorksSession()
        session.start(propertyName: "Test House", firstFloorLabel: "Ground Floor")
        XCTAssertEqual(session.scanDurationDescription, "under a minute")
    }

    func testIsSupportedMatchesAvailabilityCheck() {
        let expected: Bool
        if #available(iOS 17.0, *) { expected = true } else { expected = false }
        XCTAssertEqual(FullWorksSession.isSupported, expected)
    }

    // MARK: - finishFloor with no rooms recorded (still exercisable without CapturedRoom)

    func testFinishFloorAdvancesToNextAlreadyAddedFloor() {
        let session = FullWorksSession()
        session.start(propertyName: "Test House", firstFloorLabel: "Ground Floor")
        session.addFloor(label: "First Floor")
        session.currentFloorIndex = 0   // simulate finishing the ground floor first
        session.finishFloor()
        XCTAssertEqual(session.currentFloorIndex, 1)
        if case .betweenRooms = session.phase {} else { XCTFail("expected .betweenRooms phase") }
    }
}
