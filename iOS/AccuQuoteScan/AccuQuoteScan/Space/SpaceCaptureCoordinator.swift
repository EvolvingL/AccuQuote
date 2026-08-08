import Foundation
@preconcurrency import ARKit
import Combine
import simd

// MARK: - Space Capture State

enum SpaceCaptureState {
    case placingVolume       // aim at the detail, tap a detected plane to drop the capture volume
    case scanning            // volume placed, accumulating mesh + coverage
    case processing          // extracting OBB (or frame rectangle) from accumulated mesh
    case complete(SpaceDimensions)
    /// §3.2 "For window/door frames specifically" — reached instead of
    /// .complete when captureTarget is .frame at finishCapture() time.
    case completeFrame(FrameReveal)
    case unsupported         // no LiDAR — caller should fall back to manual entry
    case error(String)
}

/// What finishCapture() should extract from the accumulated mesh — set
/// before placeVolume() (see SpaceScanningView's target picker). A void
/// (under-sink, cupboard interior) wants a 3-axis OBB; a window/door frame
/// wants a fitted rectangle + reveal depth + square-check, which is a
/// meaningfully different measurement (§3.2 treats them as two paths, not
/// one calculation read two ways).
enum SpaceCaptureTarget: Hashable {
    case void
    case frame
}

// MARK: - SpaceCaptureCoordinator (Tri-Mode Scanning build spec §3.1–§3.2)
//
// Raw ARKit scene reconstruction session for Space mode — deliberately
// separate from ScanCoordinator rather than a new case bolted onto it: Room
// mode's coordinator is built entirely around RoomCaptureSession/CapturedRoom
// (LiDAR parametric room capture) and its own ARSession pose-fusion fallback,
// neither of which has anything to do with ARMeshAnchor scene reconstruction
// or a user-placed capture volume. Keeping this as its own MainActor object
// mirrors the existing pattern of one coordinator per genuinely distinct
// capture pipeline rather than forcing every mode through one god-object.

@MainActor
final class SpaceCaptureCoordinator: NSObject, ObservableObject, ARSessionDelegate {

    @Published var state: SpaceCaptureState = .placingVolume
    @Published var instructionText: String = "Tap the detail you want to measure"
    @Published var captureVolume: CaptureVolume?
    @Published var captureTarget: SpaceCaptureTarget = .void

    let coverageTracker = SpaceCoverageTracker()

    var arSession: ARSession?

    /// Frozen mesh vertices (world space, inside the capture volume) kept
    /// around after .complete so the review screen can offer tap-to-measure
    /// against the actual captured geometry.
    private(set) var frozenTriangles: [SpaceMeshExtraction.ExtractedTriangle] = []

    private var meshAnchors: [UUID: ARMeshAnchor] = [:]
    private var ingestTimer: Timer?

    static var isSupported: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)
    }

    // MARK: - Start / stop

    func start() {
        guard Self.isSupported else {
            state = .unsupported
            return
        }
        let session = ARSession()
        session.delegate = self
        arSession = session
        state = .placingVolume
        instructionText = "Tap the detail you want to measure"
        coverageTracker.reset()
        meshAnchors = [:]
        frozenTriangles = []
        captureVolume = nil
    }

    func configuration() -> ARWorldTrackingConfiguration {
        let config = ARWorldTrackingConfiguration()
        config.sceneReconstruction = .meshWithClassification
        var semantics: ARConfiguration.FrameSemantics = [.sceneDepth]
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            semantics.insert(.smoothedSceneDepth)
        }
        config.frameSemantics = semantics
        config.planeDetection = [.horizontal, .vertical]
        return config
    }

    func reset() {
        ingestTimer?.invalidate(); ingestTimer = nil
        arSession?.pause(); arSession = nil
        meshAnchors = [:]
        frozenTriangles = []
        captureVolume = nil
        coverageTracker.reset()
        state = .placingVolume
        instructionText = "Tap the detail you want to measure"
    }

    /// Places the capture volume at a world-space point the user tapped
    /// (already hit-tested against a detected plane by the view layer — see
    /// SpaceScanningView's tap handler). Starts accumulating mesh/coverage
    /// from this point on.
    func placeVolume(at worldPoint: SIMD3<Float>) {
        guard case .placingVolume = state else { return }
        let volume = CaptureVolume.defaultCube(at: worldPoint)
        captureVolume = volume
        coverageTracker.setVolume(volume)
        state = .scanning
        instructionText = "Move around the detail — hold steady on tricky corners"

        // Sample accumulated mesh at 4Hz — matches ScanCoordinator's
        // pose-fusion sweep rate; scene reconstruction meshes update
        // continuously in the background regardless of sampling cadence, so
        // this only controls how often we re-voxelise, not capture fidelity.
        ingestTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.ingestCurrentMesh() }
        }
    }

    /// Grows the capture volume slightly — exposed for a future "box too
    /// small" adjustment control; not yet wired to UI (§3.1 describes the
    /// volume as "adjustable", the default-cube placement above covers the
    /// common case first).
    func resizeVolume(sideLength: Float) {
        guard var volume = captureVolume else { return }
        volume = CaptureVolume(center: volume.center, size: SIMD3<Float>(repeating: sideLength), orientation: volume.orientation)
        captureVolume = volume
        coverageTracker.setVolume(volume)
    }

    private func ingestCurrentMesh() {
        guard let volume = captureVolume else { return }
        var trianglesInVolume: [SpaceMeshExtraction.ExtractedTriangle] = []
        for anchor in meshAnchors.values {
            trianglesInVolume.append(contentsOf: SpaceMeshExtraction.trianglesInsideCaptureVolume(of: anchor, volume: volume))
        }
        frozenTriangles = trianglesInVolume
        coverageTracker.ingest(worldPoints: trianglesInVolume.map { $0.centroid })

        if coverageTracker.isComplete {
            instructionText = "Capture complete — tap Done"
        } else {
            instructionText = Self.coverageInstruction(coverage: coverageTracker.coverage)
        }
    }

    static func coverageInstruction(coverage: Float) -> String {
        if coverage >= 0.92 { return "Nearly there — hold steady" }
        if coverage >= 0.60 { return "Good — check the edges and corners" }
        if coverage >= 0.25 { return "Keep going — move slowly around the detail" }
        return "Move around the detail — hold steady on tricky corners"
    }

    /// Manual Done, or auto-completion once the coverage tracker's stable-
    /// duration gate is met (checked by the view via coverageTracker.isComplete
    /// — see SpaceScanningView's onChange).
    func finishCapture() {
        guard case .scanning = state else { return }
        ingestTimer?.invalidate(); ingestTimer = nil
        state = .processing

        let triangles = frozenTriangles
        let target = captureTarget
        Task {
            let points = triangles.flatMap { [$0.v0, $0.v1, $0.v2] }

            switch target {
            case .void:
                guard let obb = SpaceMeasurement.orientedBoundingBox(of: points) else {
                    await MainActor.run {
                        self.state = .error("Not enough detail captured — try scanning again with slower, closer movements.")
                    }
                    return
                }
                let dimensions = SpaceDimensions(obb: obb, scanMethod: .lidar)
                await MainActor.run { self.state = .complete(dimensions) }

            case .frame:
                guard let rect = SpaceMeasurement.fittedRectangle(of: points) else {
                    await MainActor.run {
                        self.state = .error("Couldn't find a clear frame face — try scanning again, keeping the whole frame in the capture box.")
                    }
                    return
                }
                let corners = SpaceMeasurement.actualCorners(of: points, nearestTo: rect)
                // Reveal depth: how far points extend behind the fitted face
                // plane — the wall thickness at the opening, which is what a
                // fitter needs alongside width/height to order a replacement.
                let depthExtent = points
                    .map { abs(simd_dot($0 - rect.center, rect.planeNormal)) }
                    .max() ?? 0
                let reveal = FrameReveal(rectangle: rect, corners: corners, depth: Double(depthExtent), scanMethod: .lidar)
                await MainActor.run { self.state = .completeFrame(reveal) }
            }
        }
    }

    /// Tap-to-measure against the frozen post-capture mesh (§3.2) — nearest
    /// captured vertex to each of two screen-space taps, already unprojected
    /// to world space by the caller via a hit-test against frozenTriangles.
    func measureDistance(from a: SIMD3<Float>, to b: SIMD3<Float>) -> Float {
        SpaceMeasurement.pointToPointDistance(a, b)
    }

    // MARK: - ARSessionDelegate

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {}

    nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        updateMeshAnchors(added: anchors)
    }

    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        updateMeshAnchors(added: anchors)
    }

    nonisolated func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        let ids = anchors.compactMap { $0 as? ARMeshAnchor }.map { $0.identifier }
        guard !ids.isEmpty else { return }
        Task { @MainActor in
            for id in ids { self.meshAnchors.removeValue(forKey: id) }
        }
    }

    nonisolated private func updateMeshAnchors(added anchors: [ARAnchor]) {
        let meshes = anchors.compactMap { $0 as? ARMeshAnchor }
        guard !meshes.isEmpty else { return }
        Task { @MainActor in
            for anchor in meshes { self.meshAnchors[anchor.identifier] = anchor }
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor in self.state = .error(error.localizedDescription) }
    }
}
