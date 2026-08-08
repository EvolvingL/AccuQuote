import Foundation
import simd

// MARK: - SpaceCoverageTracker (Tri-Mode Scanning build spec §3.1)
//
// Voxel-based coverage for Space mode's small capture volume — a completely
// different model from ScanCoverageTracker's room-scale azimuth-sector
// tracking (which assumes the user walks around a room's perimeter; Space
// mode's box is ~1m³ and the user moves the phone around a fixed point, so
// "which direction is the camera facing from the room centre" doesn't apply).
//
// Pure value type: voxel state lives in a Set<VoxelIndex>, computed from
// plain SIMD3<Float> triangle centroids the caller already extracted via
// SpaceMeshExtraction. No ARKit/RoomPlan types, so it's fixture-testable
// (see DevToolsChecks) the same way SpaceMeasurement is.

struct VoxelIndex: Hashable {
    let x: Int
    let y: Int
    let z: Int
}

@MainActor
final class SpaceCoverageTracker: ObservableObject {

    static let voxelSize: Float = 0.04   // 4cm, per §3.1

    @Published private(set) var coverage: Float = 0
    @Published private(set) var isComplete: Bool = false
    /// Synthetic 24-sector breakdown so the existing CoverageRingView (built
    /// for room-scale scanning) can be reused as-is for Space mode's visual —
    /// see CoverageRingView's doc comment; it only needs sectors/coverage/
    /// isComplete, nothing room-specific.
    @Published private(set) var sectors: [SectorState] = Array(
        repeating: SectorState(azimuthHit: false, verticallySwept: false),
        count: ScanCoverageTracker.sectorCount
    )

    private var occupied: Set<VoxelIndex> = []
    private var expectedVoxelCount: Int = 1
    private var volume: CaptureVolume?
    private var stableCoverageSince: Date?

    // Completion: coverage > 92% and stable for 2s (§3.1), or manual Done.
    private static let completionThreshold: Float = 0.92
    private static let stableDuration: TimeInterval = 2.0

    func reset() {
        occupied = []
        volume = nil
        expectedVoxelCount = 1
        coverage = 0
        isComplete = false
        stableCoverageSince = nil
        sectors = Array(repeating: SectorState(azimuthHit: false, verticallySwept: false),
                        count: ScanCoverageTracker.sectorCount)
    }

    /// Called once the user places the capture volume — determines the
    /// expected voxel budget (an inscribed sphere's worth of a solid interior
    /// surface, not the full box volume: a real mesh only covers the box's
    /// inner surfaces/contents, not every interior voxel, so budgeting against
    /// the full box volume would make 100% unreachable in practice).
    func setVolume(_ volume: CaptureVolume) {
        self.volume = volume
        let voxelsPerAxis = SIMD3<Float>(
            volume.halfExtents.x * 2 / Self.voxelSize,
            volume.halfExtents.y * 2 / Self.voxelSize,
            volume.halfExtents.z * 2 / Self.voxelSize
        )
        // Surface-area proxy: two opposing faces along each axis, in voxel units.
        let faceXY: Float = voxelsPerAxis.x * voxelsPerAxis.y
        let faceYZ: Float = voxelsPerAxis.y * voxelsPerAxis.z
        let faceXZ: Float = voxelsPerAxis.x * voxelsPerAxis.z
        let totalFaceVoxels: Float = 2 * (faceXY + faceYZ + faceXZ)
        let budget: Float = totalFaceVoxels * 0.5
        expectedVoxelCount = max(1, Int(budget))
    }

    /// Feed newly-extracted world-space triangle centroids (already filtered
    /// to inside the capture volume by the caller via
    /// SpaceMeshExtraction.trianglesInsideCaptureVolume). Marks their voxels
    /// occupied and recomputes coverage/completion.
    func ingest(worldPoints: [SIMD3<Float>]) {
        guard let volume else { return }
        for point in worldPoints {
            occupied.insert(Self.voxelIndex(for: point, volumeCenter: volume.center))
        }
        recompute()
    }

    private func recompute() {
        let raw = min(1.0, Float(occupied.count) / Float(expectedVoxelCount))
        coverage = max(coverage, raw)

        if coverage >= Self.completionThreshold {
            if stableCoverageSince == nil { stableCoverageSince = Date() }
            if let since = stableCoverageSince, Date().timeIntervalSince(since) >= Self.stableDuration {
                isComplete = true
            }
        } else {
            stableCoverageSince = nil
        }

        sectors = Self.syntheticSectors(occupied: occupied, volumeCenter: volume?.center ?? .zero, coverage: coverage)
    }

    /// Manual Done — completion without waiting for the stable-coverage timer.
    func markComplete() {
        isComplete = true
    }

    // MARK: - Pure helpers (fixture-testable)

    static func voxelIndex(for point: SIMD3<Float>, volumeCenter: SIMD3<Float>) -> VoxelIndex {
        let relative = point - volumeCenter
        return VoxelIndex(
            x: Int((relative.x / voxelSize).rounded(.down)),
            y: Int((relative.y / voxelSize).rounded(.down)),
            z: Int((relative.z / voxelSize).rounded(.down))
        )
    }

    /// Bins occupied voxels into 24 angular sectors around volumeCenter (XZ
    /// plane, matching CoverageRingView's 12-o'clock-clockwise convention) so
    /// the ring has something to light up. Purely cosmetic — the real
    /// completion gate is voxel-count coverage, not this binning.
    static func syntheticSectors(occupied: Set<VoxelIndex>, volumeCenter: SIMD3<Float>, coverage: Float) -> [SectorState] {
        let count = ScanCoverageTracker.sectorCount
        var hit = Array(repeating: false, count: count)
        for voxel in occupied {
            let x = Float(voxel.x), z = Float(voxel.z)
            guard x != 0 || z != 0 else { hit[0] = true; continue }
            let angleDeg = (atan2(x, z) * 180 / Float.pi + 360).truncatingRemainder(dividingBy: 360)
            let sector = Int(angleDeg / (360.0 / Float(count))) % count
            hit[sector] = true
        }
        return (0..<count).map { i in
            SectorState(azimuthHit: hit[i], verticallySwept: hit[i] && coverage > 0.5)
        }
    }
}
