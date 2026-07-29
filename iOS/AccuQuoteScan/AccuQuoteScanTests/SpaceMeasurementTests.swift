import XCTest
import simd
@testable import AccuQuoteScan

final class SpaceMeasurementTests: XCTestCase {

    // MARK: Oriented bounding box

    func testOBBFitsAxisAlignedBox() {
        let points: [SIMD3<Float>] = [
            SIMD3(-1, -0.5, -0.25), SIMD3(1, -0.5, -0.25), SIMD3(-1, 0.5, -0.25), SIMD3(1, 0.5, -0.25),
            SIMD3(-1, -0.5,  0.25), SIMD3(1, -0.5,  0.25), SIMD3(-1, 0.5,  0.25), SIMD3(1, 0.5,  0.25),
        ]
        guard let obb = SpaceMeasurement.orientedBoundingBox(of: points) else {
            return XCTFail("orientedBoundingBox returned nil")
        }
        let dims = SpaceDimensions(obb: obb)
        XCTAssertEqual(dims.width, 2.0, accuracy: 0.02)
        XCTAssertEqual(dims.height, 1.0, accuracy: 0.02)
        XCTAssertEqual(dims.depth, 0.5, accuracy: 0.02)
        XCTAssertLessThan(simd_length(obb.center), 0.02)
    }

    func testOBBFitsRotatedOffsetBox() {
        let angle: Float = 30 * .pi / 180
        let rotation = simd_quatf(angle: angle, axis: SIMD3<Float>(0, 1, 0))
        let offset = SIMD3<Float>(3, 1, -2)
        let localCorners: [SIMD3<Float>] = [
            SIMD3(-1, -0.5, -0.25), SIMD3(1, -0.5, -0.25), SIMD3(-1, 0.5, -0.25), SIMD3(1, 0.5, -0.25),
            SIMD3(-1, -0.5,  0.25), SIMD3(1, -0.5,  0.25), SIMD3(-1, 0.5,  0.25), SIMD3(1, 0.5,  0.25),
        ]
        let worldPoints = localCorners.map { rotation.act($0) + offset }

        guard let obb = SpaceMeasurement.orientedBoundingBox(of: worldPoints) else {
            return XCTFail("orientedBoundingBox returned nil")
        }
        let dims = SpaceDimensions(obb: obb)
        XCTAssertEqual(dims.width, 2.0, accuracy: 0.02)
        XCTAssertEqual(dims.height, 1.0, accuracy: 0.02)
        XCTAssertEqual(dims.depth, 0.5, accuracy: 0.02)
        XCTAssertLessThan(simd_distance(obb.center, offset), 0.02)
    }

    func testOBBReturnsNilForFewerThanThreePoints() {
        XCTAssertNil(SpaceMeasurement.orientedBoundingBox(of: []))
        XCTAssertNil(SpaceMeasurement.orientedBoundingBox(of: [SIMD3(0, 0, 0)]))
        XCTAssertNil(SpaceMeasurement.orientedBoundingBox(of: [SIMD3(0, 0, 0), SIMD3(1, 0, 0)]))
    }

    func testOBBHandlesDegenerateCoincidentPoints() {
        // All points identical — covariance matrix is all-zero. Must not crash
        // or produce NaN/negative extents; a nil result is an acceptable,
        // safe outcome for degenerate input.
        let points = Array(repeating: SIMD3<Float>(1, 2, 3), count: 10)
        if let obb = SpaceMeasurement.orientedBoundingBox(of: points) {
            XCTAssertTrue(obb.halfExtents.x.isFinite && obb.halfExtents.x >= 0)
            XCTAssertTrue(obb.halfExtents.y.isFinite && obb.halfExtents.y >= 0)
            XCTAssertTrue(obb.halfExtents.z.isFinite && obb.halfExtents.z >= 0)
        }
        // else: nil is fine — the important thing is it didn't crash/hang.
    }

    func testOBBHandlesCollinearPoints() {
        // All points on a line (zero-variance in 2 of 3 dimensions) — a
        // degenerate but plausible real-world input (e.g. a very thin sliver
        // of mesh). Must terminate and return finite results.
        let points: [SIMD3<Float>] = (0..<20).map { SIMD3<Float>(Float($0) * 0.1, 0, 0) }
        if let obb = SpaceMeasurement.orientedBoundingBox(of: points) {
            XCTAssertTrue(obb.halfExtents.x.isFinite)
            XCTAssertTrue(obb.halfExtents.y.isFinite)
            XCTAssertTrue(obb.halfExtents.z.isFinite)
        }
    }

    // MARK: Tap-to-measure

    func testPointToPointDistance345Triangle() {
        let a = SIMD3<Float>(0, 0, 0)
        let b = SIMD3<Float>(3, 4, 0)
        XCTAssertEqual(SpaceMeasurement.pointToPointDistance(a, b), 5.0, accuracy: 0.001)
    }

    func testPointToPointDistanceZeroForSamePoint() {
        let a = SIMD3<Float>(1, 1, 1)
        XCTAssertEqual(SpaceMeasurement.pointToPointDistance(a, a), 0.0, accuracy: 0.0001)
    }

    // MARK: Frame fitting

    func testFittedRectangleSquareFrame() {
        let points: [SIMD3<Float>] = [
            SIMD3(-0.3, -0.3, 1.0), SIMD3(0.3, -0.3, 1.0),
            SIMD3(-0.3,  0.3, 1.0), SIMD3(0.3,  0.3, 1.0),
        ]
        guard let rect = SpaceMeasurement.fittedRectangle(of: points) else {
            return XCTFail("fittedRectangle returned nil")
        }
        let corners = SpaceMeasurement.actualCorners(of: points, nearestTo: rect)
        let reveal = FrameReveal(rectangle: rect, corners: corners, depth: 0.1, scanMethod: .lidar)
        XCTAssertEqual(reveal.width, 0.6, accuracy: 0.02)
        XCTAssertEqual(reveal.height, 0.6, accuracy: 0.02)
        XCTAssertTrue(reveal.isSquareWithinTolerance)
    }

    func testFittedRectangleFlagsRackedFrame() {
        let points: [SIMD3<Float>] = [
            SIMD3(-0.3, -0.3, 1.0), SIMD3(0.3, -0.3, 1.0),
            SIMD3(-0.3,  0.3, 1.0), SIMD3(0.32, 0.32, 1.0),
        ]
        guard let rect = SpaceMeasurement.fittedRectangle(of: points) else {
            return XCTFail("fittedRectangle returned nil")
        }
        let corners = SpaceMeasurement.actualCorners(of: points, nearestTo: rect)
        let reveal = FrameReveal(rectangle: rect, corners: corners, depth: 0.1, scanMethod: .lidar)
        XCTAssertFalse(reveal.isSquareWithinTolerance)
        XCTAssertGreaterThan(reveal.diagonalDeltaMM, 5.0)
    }

    func testFittedRectangleReturnsNilForFewerThanThreePoints() {
        XCTAssertNil(SpaceMeasurement.fittedRectangle(of: [SIMD3(0, 0, 0), SIMD3(1, 0, 0)]))
    }

    // MARK: SpaceQuoteAttachment copy

    func testQuoteAttachmentCopyMatchesSpecFormat() {
        let dims = SpaceDimensions(width: 0.562, height: 0.448, depth: 0.585, scanMethod: .lidar)
        let note = SpaceQuoteAttachment.note(itemLabel: "Replace kitchen sink unit", dimensions: dims)
        XCTAssertEqual(note, "Replace kitchen sink unit — void measured 562 × 448 × 585 mm")
    }

    func testFrameQuoteAttachmentFlagsOutOfSquare() {
        let points: [SIMD3<Float>] = [
            SIMD3(-0.3, -0.3, 1.0), SIMD3(0.3, -0.3, 1.0),
            SIMD3(-0.3,  0.3, 1.0), SIMD3(0.32, 0.32, 1.0),
        ]
        let rect = SpaceMeasurement.fittedRectangle(of: points)!
        let corners = SpaceMeasurement.actualCorners(of: points, nearestTo: rect)
        let reveal = FrameReveal(rectangle: rect, corners: corners, depth: 0.1, scanMethod: .lidar)
        let note = SpaceQuoteAttachment.note(itemLabel: "Replace window frame", frame: reveal)
        XCTAssertTrue(note.contains("out of square"))
    }

    // MARK: SpaceDimensions sorting convention

    func testSpaceDimensionsSortsExtentsDescending() {
        let obbLike = SpaceMeasurement.orientedBoundingBox(of: [
            SIMD3(-1, -2, -3), SIMD3(1, 2, 3), SIMD3(-1, 2, -3), SIMD3(1, -2, 3),
            SIMD3(-1, -2, 3), SIMD3(1, 2, -3), SIMD3(-1, 2, 3), SIMD3(1, -2, -3),
        ])
        guard let obb = obbLike else { return XCTFail("nil OBB") }
        let dims = SpaceDimensions(obb: obb)
        XCTAssertGreaterThanOrEqual(dims.width, dims.height)
        XCTAssertGreaterThanOrEqual(dims.height, dims.depth)
    }

    // MARK: - CaptureVolume containment (SpaceMeshExtraction.swift)

    func testCaptureVolumeAxisAlignedContainment() {
        let volume = CaptureVolume(center: .zero, size: SIMD3<Float>(1, 1, 1))
        XCTAssertTrue(volume.contains(worldPoint: SIMD3(0.4, 0.4, 0.4)))
        XCTAssertFalse(volume.contains(worldPoint: SIMD3(0.6, 0, 0)))
    }

    func testCaptureVolumeRotatedContainmentRespectsOrientation() {
        let rotation = simd_quatf(angle: .pi / 4, axis: SIMD3<Float>(0, 1, 0))
        let volume = CaptureVolume(center: .zero, size: SIMD3<Float>(1, 1, 1), orientation: rotation)

        let pointInsideWhenRotated = rotation.act(SIMD3<Float>(0, 0, 0.4))
        let pointOutsideRegardless = SIMD3<Float>(5, 5, 5)

        XCTAssertTrue(volume.contains(worldPoint: pointInsideWhenRotated))
        XCTAssertFalse(volume.contains(worldPoint: pointOutsideRegardless))
    }

    func testCaptureVolumeDefaultCubeSideLength() {
        let volume = CaptureVolume.defaultCube(at: .zero)
        XCTAssertEqual(volume.halfExtents.x * 2, CaptureVolume.defaultSideLength, accuracy: 0.001)
    }

    // MARK: - simd_quatf Codable round-trip

    func testSimdQuatfCodableRoundTrip() throws {
        let original = simd_quatf(angle: 0.7854, axis: simd_normalize(SIMD3<Float>(1, 2, 3)))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(simd_quatf.self, from: data)
        XCTAssertEqual(original.vector.x, decoded.vector.x, accuracy: 0.0001)
        XCTAssertEqual(original.vector.y, decoded.vector.y, accuracy: 0.0001)
        XCTAssertEqual(original.vector.z, decoded.vector.z, accuracy: 0.0001)
        XCTAssertEqual(original.vector.w, decoded.vector.w, accuracy: 0.0001)
    }

    func testCaptureVolumeCodableRoundTrip() throws {
        let original = CaptureVolume.defaultCube(at: SIMD3<Float>(1, 2, 3))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CaptureVolume.self, from: data)
        XCTAssertEqual(decoded.center, original.center)
        XCTAssertEqual(decoded.halfExtents, original.halfExtents)
    }

    // MARK: - Stress tests (client-side load)

    /// Feeds 60,000 points (ScanCoordinator's own maxWorldPoints cap) through
    /// the OBB fitter and asserts it completes in bounded time with a sane
    /// (non-degenerate, finite) result — this is the exact point-count a long
    /// poseFusion sweep can accumulate in production.
    func testOBBHandles60kPointsWithinBoundedTime() {
        var generator = SystemRandomNumberGenerator()
        let points: [SIMD3<Float>] = (0..<60_000).map { _ in
            SIMD3<Float>(
                Float.random(in: -2...2, using: &generator),
                Float.random(in: -1...1, using: &generator),
                Float.random(in: -1.5...1.5, using: &generator)
            )
        }

        let start = Date()
        let obb = SpaceMeasurement.orientedBoundingBox(of: points)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertNotNil(obb)
        XCTAssertLessThan(elapsed, 3.0, "OBB fit over 60k points took \(elapsed)s — too slow for a responsive UI")
        if let obb {
            XCTAssertTrue(obb.halfExtents.x.isFinite && obb.halfExtents.y.isFinite && obb.halfExtents.z.isFinite)
            XCTAssertGreaterThan(obb.halfExtents.x, 0)
        }
    }

    func testOBBPerformanceOn60kPoints() {
        var points: [SIMD3<Float>] = []
        points.reserveCapacity(60_000)
        for i in 0..<60_000 {
            let x: Float = Float(i % 200) * 0.01
            let y: Float = Float((i / 200) % 200) * 0.01
            let z: Float = Float(i % 50) * 0.02
            points.append(SIMD3<Float>(x, y, z))
        }
        measure {
            _ = SpaceMeasurement.orientedBoundingBox(of: points)
        }
    }
}
