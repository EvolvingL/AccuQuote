import XCTest
import simd
@testable import AccuQuoteScan

// MARK: - ScanQualityGateTests
//
// Ports and expands DevToolsChecks' Phase 1 checks into real XCTestCase
// assertions. Only the pure `evaluate(walls:doors:windows:floors:)` overload
// is exercised here — the CapturedRoom-taking overload (`evaluate(capturedRoom:)`)
// is a thin adapter over a framework-constructed, decode-only type with no
// public initializer, so it can only be exercised by a real device scan (see
// the existing on-device Dev Tools checklist).

final class ScanQualityGateTests: XCTestCase {

    // MARK: Clean room

    func testCleanRoomPasses() {
        let walls = (0..<4).map { i in
            WallSample(id: "wall-\(i)", lengthMetres: 3.5, leftEdgeClosed: true, rightEdgeClosed: true, confidence: .high)
        }
        let confidence = ScanQualityGate.evaluate(walls: walls)
        XCTAssertTrue(confidence.isPassing)
        XCTAssertTrue(confidence.issues.isEmpty)
        XCTAssertEqual(confidence.overallScore, 1.0)
    }

    // MARK: Open loop

    func testOpenLoopWallFlaggedBlocking() {
        var walls = (0..<4).map { i in
            WallSample(id: "wall-\(i)", lengthMetres: 3.5, leftEdgeClosed: true, rightEdgeClosed: true, confidence: .high)
        }
        walls[2] = WallSample(id: "wall-2", lengthMetres: 3.5, leftEdgeClosed: true, rightEdgeClosed: false, confidence: .high)

        let confidence = ScanQualityGate.evaluate(walls: walls)
        let openLoop = confidence.issues.first { $0.kind == .openLoop }
        XCTAssertFalse(confidence.isPassing)
        XCTAssertNotNil(openLoop)
        XCTAssertEqual(openLoop?.severity, .blocking)
        XCTAssertEqual(openLoop?.affectedSurfaceIDs, ["wall-2"])
    }

    func testBothEdgesOpenStillProducesSingleIssueForThatWall() {
        let walls = [WallSample(id: "w0", lengthMetres: 3.0, leftEdgeClosed: false, rightEdgeClosed: false, confidence: .high)]
        let confidence = ScanQualityGate.evaluate(walls: walls)
        let openLoopIssues = confidence.issues.filter { $0.kind == .openLoop }
        XCTAssertEqual(openLoopIssues.count, 1, "one open wall should produce exactly one openLoop issue, not two")
    }

    // MARK: Confidence levels

    func testLowConfidenceWallIsBlocking() {
        let walls = [WallSample(id: "w0", lengthMetres: 3.0, leftEdgeClosed: true, rightEdgeClosed: true, confidence: .low)]
        let confidence = ScanQualityGate.evaluate(walls: walls)
        let issue = confidence.issues.first { $0.kind == .lowConfidenceSurface }
        XCTAssertNotNil(issue)
        XCTAssertEqual(issue?.severity, .blocking)
        XCTAssertFalse(confidence.isPassing)
    }

    func testMediumConfidenceWallIsWarningOnly() {
        let walls = (0..<4).map { i in
            WallSample(id: "wall-\(i)", lengthMetres: 3.5, leftEdgeClosed: true, rightEdgeClosed: true,
                       confidence: i == 0 ? .medium : .high)
        }
        let confidence = ScanQualityGate.evaluate(walls: walls)
        let issue = confidence.issues.first { $0.kind == .lowConfidenceSurface }
        XCTAssertNotNil(issue)
        XCTAssertEqual(issue?.severity, .warning)
        // A single warning-only issue still fails isPassing once score drops
        // below 0.85 (4 walls, 1 issue -> score 0.88, so this specific case
        // actually still passes at 0.85 threshold — verify the score directly
        // rather than assume isPassing's outcome).
        XCTAssertEqual(confidence.overallScore, 1.0 - Float(1) * 0.12, accuracy: 0.001)
    }

    func testHighConfidenceProducesNoIssue() {
        let walls = [WallSample(id: "w0", lengthMetres: 3.0, leftEdgeClosed: true, rightEdgeClosed: true, confidence: .high)]
        let confidence = ScanQualityGate.evaluate(walls: walls)
        XCTAssertTrue(confidence.issues.isEmpty)
    }

    func testLowConfidenceFloorIsBlocking() {
        let floors = [SurfaceConfidenceSample(id: "f0", confidence: .low)]
        let confidence = ScanQualityGate.evaluate(walls: [], floors: floors)
        let issue = confidence.issues.first { $0.kind == .lowConfidenceSurface }
        XCTAssertNotNil(issue)
        XCTAssertEqual(issue?.severity, .blocking)
    }

    // MARK: Suspicious dimensions

    func testSuspiciouslyShortWallFlaggedWarning() {
        let walls = [WallSample(id: "short", lengthMetres: 0.1, leftEdgeClosed: true, rightEdgeClosed: true, confidence: .high)]
        let confidence = ScanQualityGate.evaluate(walls: walls)
        let issue = confidence.issues.first { $0.kind == .suspiciousDimension }
        XCTAssertNotNil(issue)
        XCTAssertEqual(issue?.severity, .warning)
    }

    func testExactlyBoundaryWallLengthNotFlagged() {
        // 0.2 is the exclusive upper bound in suspiciousDimensionIssues (`< 0.2`).
        let walls = [WallSample(id: "boundary", lengthMetres: 0.2, leftEdgeClosed: true, rightEdgeClosed: true, confidence: .high)]
        let confidence = ScanQualityGate.evaluate(walls: walls)
        XCTAssertNil(confidence.issues.first { $0.kind == .suspiciousDimension })
    }

    func testNonFiniteWallLengthDoesNotCrashOrFlag() {
        let walls = [WallSample(id: "bad", lengthMetres: .nan, leftEdgeClosed: true, rightEdgeClosed: true, confidence: .high)]
        let confidence = ScanQualityGate.evaluate(walls: walls)
        // guard requires isFinite, so NaN silently produces no suspiciousDimension issue
        XCTAssertNil(confidence.issues.first { $0.kind == .suspiciousDimension })
    }

    // MARK: Unmeasured openings

    func testLowConfidenceDoorFlaggedWarning() {
        let doors = [OpeningSample(confidence: .low, isDoor: true)]
        let confidence = ScanQualityGate.evaluate(walls: [], doors: doors)
        let issue = confidence.issues.first { $0.kind == .unmeasuredOpening }
        XCTAssertNotNil(issue)
        XCTAssertEqual(issue?.severity, .warning)
    }

    func testLowConfidenceWindowFlaggedWarning() {
        let windows = [OpeningSample(confidence: .low, isDoor: false)]
        let confidence = ScanQualityGate.evaluate(walls: [], windows: windows)
        let issue = confidence.issues.first { $0.kind == .unmeasuredOpening }
        XCTAssertNotNil(issue)
    }

    func testHighConfidenceOpeningsProduceNoIssue() {
        let doors = [OpeningSample(confidence: .high, isDoor: true)]
        let windows = [OpeningSample(confidence: .medium, isDoor: false)]
        let confidence = ScanQualityGate.evaluate(walls: [], doors: doors, windows: windows)
        XCTAssertTrue(confidence.issues.isEmpty)
    }

    // MARK: Score computation

    func testComputeOverallScoreNoWallsNoIssues() {
        XCTAssertEqual(ScanQualityGate.computeOverallScore(wallCount: 0, issueCount: 0), 1.0)
    }

    func testComputeOverallScoreNoWallsWithIssues() {
        XCTAssertEqual(ScanQualityGate.computeOverallScore(wallCount: 0, issueCount: 3), 0.0)
    }

    func testComputeOverallScoreClampsAtZero() {
        // 10 issues * 0.12 = 1.2 penalty, should clamp to 0, not go negative.
        XCTAssertEqual(ScanQualityGate.computeOverallScore(wallCount: 4, issueCount: 10), 0.0)
    }

    // MARK: Issue ordering

    func testIssuesSortedBlockingBeforeWarning() {
        var walls = (0..<3).map { i in
            WallSample(id: "wall-\(i)", lengthMetres: 3.5, leftEdgeClosed: true, rightEdgeClosed: true, confidence: .high)
        }
        // wall-0: suspicious (warning); wall-1: open loop (blocking)
        walls[0] = WallSample(id: "wall-0", lengthMetres: 0.1, leftEdgeClosed: true, rightEdgeClosed: true, confidence: .high)
        walls[1] = WallSample(id: "wall-1", lengthMetres: 3.5, leftEdgeClosed: false, rightEdgeClosed: true, confidence: .high)

        let confidence = ScanQualityGate.evaluate(walls: walls)
        XCTAssertGreaterThanOrEqual(confidence.issues.count, 2)
        XCTAssertEqual(confidence.issues.first?.severity, .blocking, "blocking issues must sort first")
    }

    // MARK: Empty input

    func testEmptyInputEverything() {
        let confidence = ScanQualityGate.evaluate(walls: [])
        XCTAssertTrue(confidence.issues.isEmpty)
        XCTAssertEqual(confidence.overallScore, 1.0)
        XCTAssertTrue(confidence.isPassing)
    }
}

// MARK: - ScanCoordinator.shouldPreferNew tests (patch-mode resolution)

final class ScanCoordinatorPatchResolutionTests: XCTestCase {

    func testPassingNewBeatsFailingPrior() {
        let preferNew = ScanCoordinator.shouldPreferNew(
            priorIsPassing: false, priorWallCount: 6, priorScore: 0.5,
            newIsPassing: true, newWallCount: 4, newScore: 1.0
        )
        XCTAssertTrue(preferNew)
    }

    func testSmallerPassingNewLosesToLargerPassingPrior() {
        let preferNew = ScanCoordinator.shouldPreferNew(
            priorIsPassing: true, priorWallCount: 6, priorScore: 0.9,
            newIsPassing: true, newWallCount: 2, newScore: 1.0
        )
        XCTAssertFalse(preferNew)
    }

    func testFailingNewLosesToPassingPrior() {
        let preferNew = ScanCoordinator.shouldPreferNew(
            priorIsPassing: true, priorWallCount: 4, priorScore: 0.9,
            newIsPassing: false, newWallCount: 8, newScore: 0.9
        )
        XCTAssertFalse(preferNew, "more walls never overrides a failing gate result")
    }

    func testTiedPassingAndWallCountPrefersHigherScore() {
        XCTAssertTrue(ScanCoordinator.shouldPreferNew(
            priorIsPassing: true, priorWallCount: 4, priorScore: 0.80,
            newIsPassing: true, newWallCount: 4, newScore: 0.95
        ))
        XCTAssertFalse(ScanCoordinator.shouldPreferNew(
            priorIsPassing: true, priorWallCount: 4, priorScore: 0.95,
            newIsPassing: true, newWallCount: 4, newScore: 0.80
        ))
    }

    func testExactTieScoreDefersToNew() {
        // `newScore >= priorScore` — an exact tie should prefer new (>=, not >).
        XCTAssertTrue(ScanCoordinator.shouldPreferNew(
            priorIsPassing: true, priorWallCount: 4, priorScore: 0.9,
            newIsPassing: true, newWallCount: 4, newScore: 0.9
        ))
    }
}
