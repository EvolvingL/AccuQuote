import XCTest
@testable import AccuQuoteScan

@MainActor
final class ScanCoordinatorTests: XCTestCase {

    func testSubmitManualProducesCorrectDimensions() {
        let coordinator = ScanCoordinator()
        coordinator.submitManual(length: 4.0, width: 3.0, height: 2.4)
        guard case .complete(let result) = coordinator.state else {
            return XCTFail("expected .complete state after submitManual")
        }
        XCTAssertEqual(result.length, 4.0, accuracy: 0.001)
        XCTAssertEqual(result.width, 3.0, accuracy: 0.001)
        XCTAssertEqual(result.height, 2.4, accuracy: 0.001)
        XCTAssertEqual(result.floorArea, 12.0, accuracy: 0.01)
        XCTAssertEqual(result.scanMethod, .manual)
    }

    func testSubmitManualRoundsToExpectedPrecision() {
        let coordinator = ScanCoordinator()
        coordinator.submitManual(length: 4.126, width: 3.001, height: 2.399)
        guard case .complete(let result) = coordinator.state else {
            return XCTFail("expected .complete state")
        }
        XCTAssertEqual(result.length, 4.13, accuracy: 0.001)
        XCTAssertEqual(result.width, 3.0, accuracy: 0.001)
    }

    func testSubmitCustomShapeRectangleMatchesManualEquivalent() {
        let coordinator = ScanCoordinator()
        // A 4x3 rectangle in "vertex space" scaled by 1.0 should behave like
        // a directly-entered 4x3 room.
        let vertices: [CGPoint] = [CGPoint(x: 0, y: 0), CGPoint(x: 4, y: 0), CGPoint(x: 4, y: 3), CGPoint(x: 0, y: 3)]
        coordinator.submitCustomShape(vertices: vertices, scale: 1.0, height: 2.4)
        guard case .complete(let result) = coordinator.state else {
            return XCTFail("expected .complete state")
        }
        XCTAssertEqual(result.length, 4.0, accuracy: 0.01)
        XCTAssertEqual(result.width, 3.0, accuracy: 0.01)
        XCTAssertEqual(result.floorArea, 12.0, accuracy: 0.05)
        XCTAssertEqual(result.wallCount, 4)
    }

    func testSubmitCustomShapeAppliesScaleFactor() {
        let coordinator = ScanCoordinator()
        let vertices: [CGPoint] = [CGPoint(x: 0, y: 0), CGPoint(x: 2, y: 0), CGPoint(x: 2, y: 2), CGPoint(x: 0, y: 2)]
        coordinator.submitCustomShape(vertices: vertices, scale: 2.0, height: 2.4)
        guard case .complete(let result) = coordinator.state else {
            return XCTFail("expected .complete state")
        }
        // 2x2 vertex-space square scaled by 2.0 -> 4x4m real room.
        XCTAssertEqual(result.length, 4.0, accuracy: 0.01)
        XCTAssertEqual(result.width, 4.0, accuracy: 0.01)
    }

    func testSubmitCustomShapeTriangleUsesShoelaceArea() {
        let coordinator = ScanCoordinator()
        // Right triangle: legs 4 and 3 -> area 6.
        let vertices: [CGPoint] = [CGPoint(x: 0, y: 0), CGPoint(x: 4, y: 0), CGPoint(x: 0, y: 3)]
        coordinator.submitCustomShape(vertices: vertices, scale: 1.0, height: 2.4)
        guard case .complete(let result) = coordinator.state else {
            return XCTFail("expected .complete state")
        }
        XCTAssertEqual(result.floorArea, 6.0, accuracy: 0.05)
        XCTAssertEqual(result.wallCount, 3)
    }

    func testSubmitCustomShapeRejectsNonFiniteScale() {
        let coordinator = ScanCoordinator()
        let vertices: [CGPoint] = [CGPoint(x: 0, y: 0), CGPoint(x: 4, y: 0), CGPoint(x: 4, y: 3)]
        coordinator.submitCustomShape(vertices: vertices, scale: .nan, height: 2.4)
        guard case .error = coordinator.state else {
            return XCTFail("non-finite scale must produce .error, not a garbage .complete result")
        }
    }

    func testSubmitCustomShapeRejectsZeroScale() {
        let coordinator = ScanCoordinator()
        let vertices: [CGPoint] = [CGPoint(x: 0, y: 0), CGPoint(x: 4, y: 0), CGPoint(x: 4, y: 3)]
        coordinator.submitCustomShape(vertices: vertices, scale: 0, height: 2.4)
        guard case .error = coordinator.state else {
            return XCTFail("zero scale must be rejected")
        }
    }

    func testSubmitCustomShapeRejectsNonFiniteHeight() {
        let coordinator = ScanCoordinator()
        let vertices: [CGPoint] = [CGPoint(x: 0, y: 0), CGPoint(x: 4, y: 0), CGPoint(x: 4, y: 3)]
        coordinator.submitCustomShape(vertices: vertices, scale: 1.0, height: .infinity)
        guard case .error = coordinator.state else {
            return XCTFail("non-finite height must be rejected")
        }
    }

    func testSubmitCustomShapeRejectsNonFiniteVertex() {
        let coordinator = ScanCoordinator()
        let vertices: [CGPoint] = [CGPoint(x: 0, y: 0), CGPoint(x: CGFloat.nan, y: 0), CGPoint(x: 4, y: 3)]
        coordinator.submitCustomShape(vertices: vertices, scale: 1.0, height: 2.4)
        guard case .error = coordinator.state else {
            return XCTFail("non-finite vertex coordinate must be rejected")
        }
    }

    func testSubmitCustomShapeRequiresAtLeastThreeVertices() {
        let coordinator = ScanCoordinator()
        coordinator.submitCustomShape(vertices: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)], scale: 1.0, height: 2.4)
        // guard n >= 3 else { return } — state should remain .ready (untouched), not crash.
        guard case .ready = coordinator.state else {
            return XCTFail("fewer than 3 vertices should leave state untouched")
        }
    }

    // MARK: - Reset / re-entrancy stress

    func testResetReturnsToReadyState() {
        let coordinator = ScanCoordinator()
        coordinator.submitManual(length: 4, width: 3, height: 2.4)
        coordinator.reset()
        guard case .ready = coordinator.state else {
            return XCTFail("expected .ready after reset()")
        }
        XCTAssertEqual(coordinator.frameCount, 0)
        XCTAssertEqual(coordinator.scanProgress, 0)
    }

    func testRepeatedResetStartScanCyclesDoNotCorruptState() {
        // Simulates rapid navigation in/out of the scan flow — a real launch-day
        // failure mode if a user backgrounds/foregrounds repeatedly during a scan.
        let coordinator = ScanCoordinator()
        for i in 0..<200 {
            coordinator.reset()
            coordinator.submitManual(length: Double(4 + i % 5), width: 3, height: 2.4)
            coordinator.reset()
        }
        guard case .ready = coordinator.state else {
            return XCTFail("state must settle back to .ready after 200 reset/submit cycles")
        }
        XCTAssertEqual(coordinator.frameCount, 0)
    }

    func testCoordinatorInitDoesNotCrashRegardlessOfSimulatorCapabilities() {
        // scanMethod is determined at init from RoomCaptureSession.isSupported —
        // on the Simulator this is always false, so scanMethod resolves to
        // .poseFusion. Just confirms init/instructionText wiring doesn't crash
        // and is internally consistent.
        let coordinator = ScanCoordinator()
        XCTAssertFalse(coordinator.instructionText.isEmpty)
    }

    // MARK: - Coverage instruction text (pure function)

    func testCoverageInstructionProgressesWithCoverage() {
        let coordinator = ScanCoordinator()
        XCTAssertEqual(coordinator.coverageInstruction(coverage: 1.0, wallCount: nil), "Scan complete — tap Done")
        XCTAssertTrue(coordinator.coverageInstruction(coverage: 0.85, wallCount: nil).contains("Nearly there"))
        XCTAssertTrue(coordinator.coverageInstruction(coverage: 0.65, wallCount: nil).contains("ceiling"))
        XCTAssertTrue(coordinator.coverageInstruction(coverage: 0.30, wallCount: 3).contains("3 walls"))
        XCTAssertTrue(coordinator.coverageInstruction(coverage: 0.0, wallCount: nil).contains("Walk to the centre"))
    }

    func testCoverageInstructionSingularWallGrammar() {
        let coordinator = ScanCoordinator()
        XCTAssertTrue(coordinator.coverageInstruction(coverage: 0.30, wallCount: 1).contains("1 wall found"))
    }

    // MARK: - stubbedResult fallback

    func testStubbedResultProducesSaneDefaults() {
        let result = ScanCoordinator.stubbedResult(method: .poseFusion)
        XCTAssertGreaterThan(result.length, 0)
        XCTAssertGreaterThan(result.width, 0)
        XCTAssertEqual(result.scanMethod, .poseFusion)
    }

    // MARK: - Double numeric helpers

    func testDoubleClamped() {
        XCTAssertEqual((5.0).clamped(1.5, 15.0), 5.0)
        XCTAssertEqual((0.5).clamped(1.5, 15.0), 1.5)
        XCTAssertEqual((20.0).clamped(1.5, 15.0), 15.0)
    }

    func testDoubleRoundedToPlaces() {
        XCTAssertEqual((4.12649).rounded(to: 2), 4.13)
        XCTAssertEqual((4.124).rounded(to: 2), 4.12)
        XCTAssertEqual((4.0).rounded(to: 2), 4.0)
    }
}

// MARK: - RoomDimensions computed properties

final class RoomDimensionsTests: XCTestCase {

    func testWallAreaFormula() {
        let dims = RoomDimensions(length: 4, width: 3, height: 2.4, floorArea: 12, wallCount: 4, doorCount: 1, windowCount: 2, roomType: "bedroom", scanMethod: .manual)
        // wallArea = 2 * (length + width) * height = 2 * 7 * 2.4 = 33.6
        XCTAssertEqual(dims.wallArea, 33.6, accuracy: 0.001)
    }

    func testFormattedStringsUseExpectedPrecision() {
        let dims = RoomDimensions(length: 4.126, width: 3.001, height: 2.399, floorArea: 12.345, wallCount: 4, doorCount: 1, windowCount: 2, roomType: "bedroom", scanMethod: .manual)
        XCTAssertEqual(dims.lengthStr, "4.13")
        XCTAssertEqual(dims.widthStr, "3.00")
        XCTAssertEqual(dims.heightStr, "2.40")
        XCTAssertEqual(dims.floorAreaStr, "12.3")
    }
}

// MARK: - ScanMethod display metadata

final class ScanMethodTests: XCTestCase {

    func testDisplayNamesAreDistinctAndNonEmpty() {
        let methods: [ScanMethod] = [.lidar, .poseFusion, .manual]
        let names = Set(methods.map { $0.displayName })
        XCTAssertEqual(names.count, 3, "each scan method should have a distinct display name")
        XCTAssertTrue(names.allSatisfy { !$0.isEmpty })
    }

    func testScanMethodCodableRoundTrip() throws {
        for method in [ScanMethod.lidar, .poseFusion, .manual] {
            let data = try JSONEncoder().encode(method)
            let decoded = try JSONDecoder().decode(ScanMethod.self, from: data)
            XCTAssertEqual(decoded, method)
        }
    }
}

// MARK: - ScanErrorClassifier (Fix #11)

final class ScanErrorClassifierTests: XCTestCase {

    func testSubscriptionRequiredIsNotRetryable() {
        XCTAssertFalse(ScanErrorClassifier.isRetryable("subscription_required"))
        XCTAssertFalse(ScanErrorClassifier.isRetryable("Subscription required to continue"))
    }

    func testAuthErrorsAreNotRetryable() {
        XCTAssertFalse(ScanErrorClassifier.isRetryable("User is not authenticated"))
        XCTAssertFalse(ScanErrorClassifier.isRetryable("Please sign in to continue"))
    }

    func testGenericScanFailureIsRetryable() {
        XCTAssertTrue(ScanErrorClassifier.isRetryable("Scan session ended — starting a fresh scan instead."))
        XCTAssertTrue(ScanErrorClassifier.isRetryable("LiDAR not available on this device."))
    }

    func testIsRetryableIsCaseInsensitive() {
        XCTAssertFalse(ScanErrorClassifier.isRetryable("SUBSCRIPTION REQUIRED"))
        XCTAssertFalse(ScanErrorClassifier.isRetryable("Sign In required"))
    }

    func testFriendlyMessageMapsInterruption() {
        let msg = ScanErrorClassifier.friendlyMessage(for: "Session was interrupted")
        XCTAssertEqual(msg, "Scanning was interrupted. Please try again.")
    }

    func testFriendlyMessageMapsTrackingLoss() {
        let msg = ScanErrorClassifier.friendlyMessage(for: "World tracking failure")
        XCTAssertTrue(msg.localizedCaseInsensitiveContains("lost track"))
    }

    func testFriendlyMessageFallsBackForUnrecognisedErrors() {
        let msg = ScanErrorClassifier.friendlyMessage(for: "NSInvalidArgumentException: xyz123")
        XCTAssertEqual(msg, "Something went wrong while scanning. Please try again.")
    }
}
