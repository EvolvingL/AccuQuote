import XCTest
import simd
@testable import AccuQuoteScan

@MainActor
final class SpaceCoverageTrackerTests: XCTestCase {

    func testVoxelIndexQuantisesCorrectly() {
        let center = SIMD3<Float>.zero
        // voxelSize is 0.04 — a point at 0.05 should land in voxel index 1 (floor(0.05/0.04) = 1)
        let idx = SpaceCoverageTracker.voxelIndex(for: SIMD3(0.05, 0.05, 0.05), volumeCenter: center)
        XCTAssertEqual(idx, VoxelIndex(x: 1, y: 1, z: 1))
    }

    func testVoxelIndexHandlesNegativeCoordinatesViaFloorRounding() {
        // -0.01 / 0.04 = -0.25, floor -> -1 (not 0, which a naive Int() truncation would give)
        let idx = SpaceCoverageTracker.voxelIndex(for: SIMD3(-0.01, 0, 0), volumeCenter: .zero)
        XCTAssertEqual(idx.x, -1)
    }

    func testVoxelIndexRelativeToVolumeCenter() {
        let center = SIMD3<Float>(1, 1, 1)
        let idxAtCenter = SpaceCoverageTracker.voxelIndex(for: center, volumeCenter: center)
        XCTAssertEqual(idxAtCenter, VoxelIndex(x: 0, y: 0, z: 0))
    }

    func testResetClearsCoverageAndCompletion() {
        let tracker = SpaceCoverageTracker()
        tracker.setVolume(CaptureVolume.defaultCube(at: .zero))
        tracker.ingest(worldPoints: [SIMD3(0, 0, 0), SIMD3(0.1, 0, 0)])
        tracker.reset()
        XCTAssertEqual(tracker.coverage, 0)
        XCTAssertFalse(tracker.isComplete)
    }

    func testIngestIncreasesCoverageMonotonically() {
        let tracker = SpaceCoverageTracker()
        tracker.setVolume(CaptureVolume.defaultCube(at: .zero))
        tracker.ingest(worldPoints: [SIMD3(0, 0, 0)])
        let afterFirst = tracker.coverage
        tracker.ingest(worldPoints: (0..<200).map { SIMD3<Float>(Float($0) * 0.01 - 1, 0, 0) })
        let afterSecond = tracker.coverage
        XCTAssertGreaterThanOrEqual(afterSecond, afterFirst, "coverage must never decrease — recompute() takes max(coverage, raw)")
    }

    func testMarkCompleteForcesCompletionImmediately() {
        let tracker = SpaceCoverageTracker()
        tracker.setVolume(CaptureVolume.defaultCube(at: .zero))
        XCTAssertFalse(tracker.isComplete)
        tracker.markComplete()
        XCTAssertTrue(tracker.isComplete)
    }

    func testIngestWithoutVolumeSetIsANoOp() {
        let tracker = SpaceCoverageTracker()
        // No setVolume() called — ingest should just return early, not crash.
        tracker.ingest(worldPoints: [SIMD3(0, 0, 0), SIMD3(1, 1, 1)])
        XCTAssertEqual(tracker.coverage, 0)
    }

    func testSyntheticSectorsProducesCorrectCount() {
        let sectors = SpaceCoverageTracker.syntheticSectors(occupied: [], volumeCenter: .zero, coverage: 0)
        XCTAssertEqual(sectors.count, ScanCoverageTracker.sectorCount)
    }

    func testSyntheticSectorsMarksOriginAsSectorZero() {
        let occupied: Set<VoxelIndex> = [VoxelIndex(x: 0, y: 0, z: 0)]
        let sectors = SpaceCoverageTracker.syntheticSectors(occupied: occupied, volumeCenter: .zero, coverage: 0.5)
        XCTAssertTrue(sectors[0].azimuthHit)
    }

    // MARK: - Stress: many voxels ingested in a tight loop

    func testIngestingManyPointsStaysWithinBoundedTime() {
        let tracker = SpaceCoverageTracker()
        tracker.setVolume(CaptureVolume(center: .zero, size: SIMD3<Float>(2, 2, 2)))

        var points: [SIMD3<Float>] = []
        points.reserveCapacity(20_000)
        for i in 0..<20_000 {
            let t = Float(i)
            points.append(SIMD3<Float>(
                (t.truncatingRemainder(dividingBy: 100) - 50) * 0.02,
                (t.truncatingRemainder(dividingBy: 37) - 18) * 0.02,
                (t.truncatingRemainder(dividingBy: 53) - 26) * 0.02
            ))
        }

        let start = Date()
        tracker.ingest(worldPoints: points)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 3.0, "ingesting 20k points took \(elapsed)s")
        XCTAssertGreaterThan(tracker.coverage, 0)
        XCTAssertLessThanOrEqual(tracker.coverage, 1.0)
    }
}
