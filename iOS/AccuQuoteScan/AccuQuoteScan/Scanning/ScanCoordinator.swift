import Foundation
import RoomPlan
@preconcurrency import ARKit
import AVFoundation
import UIKit
import Combine
import simd

// MARK: - Scan Method

// Codable added for SpaceDimensions (SpaceMeasurement.swift) — Space mode's
// canonical geometry model persists as JSON per §5.1, so every field it
// carries, including scanMethod, needs to round-trip. Purely additive:
// RoomDimensions (which also has a scanMethod field) has never needed this
// since it's persisted indirectly via SavedQuote's own separate fields, not
// encoded directly.
enum ScanMethod: Codable {
    case lidar          // RoomPlan — iPhone 12 Pro+ (LiDAR)
    case poseFusion     // ARKit world tracking + point cloud bounding box — any ARKit device
    case manual         // User entered dimensions with tape measure

    var displayName: String {
        switch self {
        case .lidar:      return "LiDAR Scan"
        case .poseFusion: return "Camera Sweep"
        case .manual:     return "Manual Entry"
        }
    }

    var accuracyLabel: String {
        switch self {
        case .lidar:      return "High precision · LiDAR"
        case .poseFusion: return "Camera sweep · ±5–10cm"
        case .manual:     return "Tape measure · exact"
        }
    }

    var accuracyHex: String {
        switch self {
        case .lidar:      return "#22C55E"
        case .poseFusion: return "#3B82F6"
        case .manual:     return "#22C55E"
        }
    }
}

// MARK: - Scan Result

struct RoomDimensions {
    let length: Double
    let width: Double
    let height: Double
    let floorArea: Double
    let wallCount: Int
    let doorCount: Int
    let windowCount: Int
    let roomType: String
    let scanMethod: ScanMethod

    var lengthStr: String { String(format: "%.2f", length) }
    var widthStr:  String { String(format: "%.2f", width) }
    var heightStr: String { String(format: "%.2f", height) }
    var floorAreaStr: String { String(format: "%.1f", floorArea) }
    var wallArea: Double { 2 * (length + width) * height }
}

// MARK: - Scan State

enum ScanState {
    case ready
    case scanning
    case processing
    case complete(RoomDimensions)
    // Tri-Mode Scanning build spec §5.4: entered instead of .complete when
    // ScanQualityGate finds a blocking issue on a LiDAR scan (manual entry,
    // custom shape, and poseFusion have no CapturedRoom to gate — see
    // ScanQualityGate.swift's header comment). Carries the raw CapturedRoom
    // (so a re-scan/patch has real geometry to work with) alongside the
    // already-extracted RoomDimensions and the confidence report driving the
    // Review & Guided Re-scan screen.
    //
    // ⚠️ Phase-ordering marker: ScanNeedsReviewView (AccuQuoteScan) is
    // currently text/list-only — no partial 3D model preview, unlike
    // AccuScan's version which uses ModelViewer3D. AccuQuoteScan has no 3D
    // viewer yet (that's Phase 3 — ScanViewer3D). Once Phase 3 lands, revisit
    // ScanNeedsReviewView.swift and add the model preview to match AccuScan.
    case needsReview(CapturedRoom, RoomDimensions, ScanConfidence)
    case error(String)
}

// MARK: - LiDAR Delegate Bridge

@objc(AQSessionBridge)
private final class SessionBridge: NSObject, RoomCaptureSessionDelegate, RoomCaptureViewDelegate {
    var onUpdate: ((CapturedRoom) -> Void)?
    var onEnd:    ((CapturedRoomData, Error?) -> Void)?

    override init() { super.init() }
    required init?(coder: NSCoder) { fatalError() }
    func encode(with coder: NSCoder) { fatalError() }

    func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        onUpdate?(room)
    }
    func captureSession(_ session: RoomCaptureSession,
                        didEndWith data: CapturedRoomData, error: Error?) {
        onEnd?(data, error)
    }
    func captureSession(_ session: RoomCaptureSession, didStartWith configuration: RoomCaptureSession.Configuration) {}
    func captureSession(_ session: RoomCaptureSession, didProvide instruction: RoomCaptureSession.Instruction) {}
    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData,
                     error: Error?) -> Bool { true }
    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {}
}

// MARK: - ScanCoordinator

@MainActor
final class ScanCoordinator: ObservableObject {

    // didSet (not a manual toggle at every call site) so ScanStorageManager's
    // scan-in-progress guard can never go stale — every one of this file's
    // many `state = ...` assignments (startLiDAR, startPoseFusion, reset(),
    // submitManual, submitCustomShape, acceptWithWarnings, ...) updates the
    // guard automatically instead of needing to remember to touch it too.
    @Published var state: ScanState = .ready {
        didSet {
            switch state {
            case .scanning, .processing:
                ScanStorageManager.isScanInProgress = true
            case .ready, .complete, .needsReview, .error:
                ScanStorageManager.isScanInProgress = false
            }
        }
    }
    @Published var instructionText: String = ""
    @Published var scanProgress: Float = 0.0
    @Published var frameCount: Int = 0

    // Tri-Mode Scanning build spec §6 — ScanViewer3D needs the raw geometry,
    // not just the extracted RoomDimensions. Kept as a side-channel property
    // rather than added to ScanState.complete's associated value so the two
    // existing `case .complete(let result):` call sites (ContentView,
    // GuestScanView) don't all need updating for a value most of them never
    // use. nil for poseFusion/manual/custom-shape completions (no CapturedRoom
    // exists for those methods) — ResultView falls back to a dimensions-only
    // view when this is nil, same as it always has.
    @Published var lastCapturedRoom: CapturedRoom?

    let coverageTracker = ScanCoverageTracker()

    // Determined once at init — LiDAR if available and iOS < 26 (iOS 26 beta has broken RoomPlan),
    // otherwise poseFusion.
    let scanMethod: ScanMethod = {
        guard RoomCaptureSession.isSupported else { return .poseFusion }
        if #available(iOS 26, *) {
            // RoomPlan is broken on iOS 26 beta (black screen, "Frame has no valid depth").
            // Fall back to ARKit poseFusion path until Apple fixes it.
            return .poseFusion
        }
        return .lidar
    }()

    // LiDAR
    private var lidarSession: RoomCaptureSession?
    private var bridge: SessionBridge?
    var captureView: RoomCaptureView?

    // Pose fusion
    var arSession: ARSession?
    private var sweepTimer: Timer?
    private var worldPoints: [SIMD3<Float>] = []   // accumulated surface points in world space
    private var lastCameraPos: SIMD3<Float>?
    private var distanceTravelled: Float = 0

    // M-SC1: hard cap on accumulated points. A long camera sweep samples a
    // ~16px depth grid at 4 Hz, which would otherwise grow worldPoints without
    // bound and exhaust memory on a big room. Once full we drop incoming points
    // (the early sweep already captured the room extents the bounding box needs).
    private static let maxWorldPoints = 60_000

    init() {
        instructionText = scanMethod == .lidar
            ? "Walk slowly around the room"
            : "Hold the button and sweep the camera around every wall"
    }

    // MARK: - Start / Stop

    func startScan() {
        switch scanMethod {
        case .lidar:      startLiDAR()
        case .poseFusion: startPoseFusion()
        case .manual:     break  // manual is driven by the view
        }
    }

    func stopScan() {
        switch scanMethod {
        case .lidar:      lidarSession?.stop(); state = .processing
        case .poseFusion: stopPoseFusion()
        case .manual:     break
        }
    }

    func submitManual(length: Double, width: Double, height: Double) {
        let area = length * width
        let result = RoomDimensions(
            length: length.rounded(to: 2), width: width.rounded(to: 2),
            height: height.rounded(to: 2), floorArea: (area * 100).rounded() / 100,
            wallCount: 4, doorCount: 1, windowCount: 1,
            roomType: ScanCoordinator.guessRoomType(area: area, windows: 1),
            scanMethod: .manual
        )
        state = .complete(result)
    }

    /// Submit a custom polygon floor shape defined by vertices in metres.
    /// Uses the shoelace formula for area; bounding box for length/width.
    func submitCustomShape(vertices: [CGPoint], scale: Double, height: Double) {
        // Shoelace formula for polygon area (vertices in metres)
        let n = vertices.count
        guard n >= 3 else { return }

        // C4: validate every numeric input before it can flow into a persisted
        // quote. A non-finite scale/height/vertex would yield NaN dimensions that
        // crash Int()/JSONSerialization downstream, and a non-positive scale would
        // produce a zero-area room. Reject and surface an error instead of trapping.
        guard scale.isFinite, scale > 0, height.isFinite, height > 0,
              vertices.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            state = .error("Couldn't read those measurements. Please re-enter the shape.")
            return
        }

        var shoelace: Double = 0
        for i in 0..<n {
            let j = (i + 1) % n
            shoelace += Double(vertices[i].x) * Double(vertices[j].y)
            shoelace -= Double(vertices[j].x) * Double(vertices[i].y)
        }
        let area = abs(shoelace) / 2.0 * scale * scale

        // Bounding box for length/width approximation. xs/ys are non-empty
        // (n >= 3) and finite (validated above), so max()/min() are safe.
        let xs = vertices.map { Double($0.x) * scale }
        let ys = vertices.map { Double($0.y) * scale }
        let length = (xs.max()! - xs.min()!).rounded(to: 2)
        let width  = (ys.max()! - ys.min()!).rounded(to: 2)

        let result = RoomDimensions(
            length: length, width: width,
            height: height.rounded(to: 2),
            floorArea: (area * 100).rounded() / 100,
            wallCount: n,
            doorCount: 1, windowCount: 1,
            roomType: ScanCoordinator.guessRoomType(area: area, windows: 1),
            scanMethod: .manual
        )
        state = .complete(result)
    }

    /// Accepts a .needsReview scan with only warning-level issues (never
    /// reachable with a blocking issue present — see ScanNeedsReviewView's
    /// "Use anyway" button, only shown when hasBlockingIssues is false).
    /// Completes the scan exactly as if it had passed the gate outright.
    func acceptWithWarnings(room: CapturedRoom, result: RoomDimensions) {
        lastCapturedRoom = room
        state = .complete(result)
    }

    func reset() {
        NotificationCenter.default.removeObserver(self)
        lidarSession?.stop(); lidarSession = nil; bridge = nil; captureView = nil
        sweepTimer?.invalidate(); sweepTimer = nil
        arSession?.pause(); arSession = nil
        worldPoints = []; lastCameraPos = nil; distanceTravelled = 0
        frameCount = 0; state = .ready; scanProgress = 0
        lastCapturedRoom = nil
        coverageTracker.reset()
        instructionText = scanMethod == .lidar
            ? "Walk slowly around the room"
            : "Hold the button and sweep the camera around every wall"
    }

    // MARK: - LiDAR path

    // Set only during a patch-mode re-scan (startPatchScan) — the room/
    // confidence being fixed, kept so bridge.onEnd can pick the better of the
    // pre-patch and post-patch results (see ScanCoordinator.shouldPreferNew).
    // nil outside patch mode.
    private var priorRoomForPatch: CapturedRoom?
    private var priorConfidenceForPatch: ScanConfidence?

    /// True when the existing RoomCaptureSession is still alive and can be
    /// resumed for patch-mode re-scan. AccuQuoteScan (unlike AccuScan) never
    /// tears down lidarSession/bridge on view disappearance — only reset()
    /// does, and nothing calls reset() automatically when navigating from
    /// .scanning to .needsReview — so this is normally true right after a
    /// scan completes into review.
    var canResumeForPatchMode: Bool { lidarSession != nil && bridge != nil }

    /// Tri-Mode Scanning build spec §5.4 step 3 — re-enters live scanning to
    /// fix flagged areas. Resumes the SAME RoomCaptureSession (does not
    /// create a fresh one) so the new capture is intended to land in the same
    /// coordinate space as `priorRoom`, avoiding a full re-scan.
    ///
    /// This codebase has never previously exercised "call run() again on a
    /// session that already ran" — AccuQuoteScan's normal startLiDAR() always
    /// constructs a fresh RoomCaptureSession per scan, and RoomPlan's resume
    /// behaviour on an existing session is undocumented at the public API
    /// level. Rather than assume it resumes cleanly, completion always picks
    /// whichever result is actually better (see shouldPreferNew) — if resume
    /// behaves oddly, the user just sees the review screen again instead of
    /// silently losing their original scan.
    func startPatchScan(priorRoom: CapturedRoom, priorConfidence: ScanConfidence) {
        guard canResumeForPatchMode else {
            state = .error("Scan session ended — starting a fresh scan instead.")
            return
        }
        priorRoomForPatch = priorRoom
        priorConfidenceForPatch = priorConfidence
        coverageTracker.reset()
        scanProgress = 0
        state = .scanning
        instructionText = "Re-scan the flagged areas — walk back and cover them again"
        // Re-run the existing session directly (not startLiDAR(), which always
        // builds a fresh RoomCaptureSession) — beginLiDARSession(), triggered
        // by the new LiDARHostVC's viewDidAppear once the scanning view
        // re-renders, calls runLiDARSession() which does session.run(...) on
        // this same lidarSession.
    }

    private func startLiDAR() {
        guard RoomCaptureSession.isSupported else {
            state = .error("LiDAR not available on this device.")
            return
        }
        let bridge  = SessionBridge()
        let session = RoomCaptureSession()
        self.bridge = bridge
        self.lidarSession = session

        bridge.onUpdate = { [weak self] room in
            guard let self else { return }
            let n = room.walls.count
            Task { @MainActor in
                if let frame = self.lidarSession?.arSession.currentFrame {
                    self.coverageTracker.ingest(frame)
                }
                let cov = self.coverageTracker.coverage
                self.scanProgress    = max(min(Float(n) / 6.0, 0.95), cov * 0.95)
                self.instructionText = self.coverageInstruction(coverage: cov, wallCount: n)
            }
        }

        bridge.onEnd = { [weak self] data, error in
            guard let self else { return }
            if let error {
                let friendly = ScanErrorClassifier.friendlyMessage(for: error.localizedDescription)
                Task { @MainActor in self.state = .error(friendly) }
                return
            }
            Task { @MainActor in self.state = .processing }
            Task {
                do {
                    let room = try await RoomBuilder(options: []).capturedRoom(from: data)

                    // Patch mode: compare against the prior result rather than
                    // unconditionally accepting the new one — see
                    // startPatchScan's doc comment for why. Read both
                    // MainActor-isolated properties in one hop instead of two
                    // separate `await self.x` reads (which the compiler
                    // correctly flags as not actually needing a suspension
                    // each, since they're plain stored-property reads).
                    let patchState: (room: CapturedRoom, confidence: ScanConfidence)? = await MainActor.run {
                        guard let priorRoom = self.priorRoomForPatch,
                              let priorConfidence = self.priorConfidenceForPatch else { return nil }
                        self.priorRoomForPatch = nil
                        self.priorConfidenceForPatch = nil
                        return (priorRoom, priorConfidence)
                    }
                    if let priorRoom = patchState?.room, let priorConfidence = patchState?.confidence {
                        let newConfidence = ScanQualityGate.evaluate(capturedRoom: room)
                        let preferNew = ScanCoordinator.shouldPreferNew(
                            priorIsPassing: priorConfidence.isPassing, priorWallCount: priorRoom.walls.count, priorScore: priorConfidence.overallScore,
                            newIsPassing: newConfidence.isPassing, newWallCount: room.walls.count, newScore: newConfidence.overallScore
                        )
                        let (finalRoom, finalConfidence) = preferNew ? (room, newConfidence) : (priorRoom, priorConfidence)
                        let result = ScanCoordinator.resultFromLiDAR(finalRoom)
                        await MainActor.run {
                            if finalConfidence.isPassing {
                                self.lastCapturedRoom = finalRoom
                                self.state = .complete(result)
                            } else {
                                self.state = .needsReview(finalRoom, result, finalConfidence)
                            }
                        }
                        return
                    }

                    let result = ScanCoordinator.resultFromLiDAR(room)
                    let confidence = ScanQualityGate.evaluate(capturedRoom: room)
                    await MainActor.run {
                        if confidence.isPassing {
                            self.lastCapturedRoom = room
                            self.state = .complete(result)
                        } else {
                            self.state = .needsReview(room, result, confidence)
                        }
                    }
                } catch {
                    let friendly = ScanErrorClassifier.friendlyMessage(for: error.localizedDescription)
                    await MainActor.run { self.state = .error(friendly) }
                }
            }
        }

        session.delegate = bridge
        // captureView is created in prepareLiDARView() once the VC is on screen
        state = .scanning
    }

    /// Called by LiDARHostVC.loadView — wires the already-created RoomCaptureView
    /// (which IS the root view) to the session delegate.
    func setCaptureView(_ view: RoomCaptureView) {
        guard let bridge = bridge else { return }
        view.delegate = bridge
        captureView = view
    }

    /// Called by LiDARScanningView.onAppear — view is on screen, Metal is ready.
    func beginLiDARSession() {
        // Check permission synchronously — by this point the user has already
        // granted access (we request it on first app launch via Info.plist).
        // Running session.run() must happen on the main thread.
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .authorized {
            runLiDARSession()
        } else if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard granted else { return }
                DispatchQueue.main.async { self?.runLiDARSession() }
            }
        } else {
            state = .error("Camera access denied. Go to Settings → Privacy & Security → Camera and enable AccuQuote.")
            return
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionInterruptionEnded),
            name: NSNotification.Name(rawValue: "ARSessionInterruptionEnded"),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleForeground),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    private func runLiDARSession() {
        guard let session = lidarSession else { return }
        session.run(configuration: RoomCaptureSession.Configuration())
    }

    @objc private func handleSessionInterruptionEnded() {
        guard case .scanning = state else { return }
        runLiDARSession()
    }

    @objc private func handleForeground() {
        guard case .scanning = state else { return }
        // Delay slightly to let iOS fully hand back the camera
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.runLiDARSession()
        }
    }

    // MARK: - Pose fusion path

    func arConfiguration() -> ARWorldTrackingConfiguration {
        let config = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics = [.sceneDepth]
        }
        return config
    }

    private func startPoseFusion() {
        let session = ARSession()
        // Do NOT call session.run() here — ARViewRepresentable runs the session
        // once the ARSCNView is in the view hierarchy, so Metal has a valid drawable.
        arSession        = session
        worldPoints      = []
        lastCameraPos    = nil
        distanceTravelled = 0
        frameCount       = 0
        state            = .scanning
        scanProgress     = 0
        instructionText  = "Walk slowly — sweep camera across every wall"

        // Sample at 4 Hz — enough resolution without hammering memory
        sweepTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard let frame = session.currentFrame else { return }
                self.ingestFrame(frame)
            }
        }
    }

    private func ingestFrame(_ frame: ARFrame) {
        let camTransform = frame.camera.transform
        let camPos       = SIMD3<Float>(camTransform.columns.3.x,
                                        camTransform.columns.3.y,
                                        camTransform.columns.3.z)

        // Accumulate distance walked (guard against non-finite camera transforms
        // during tracking loss, which would poison distanceTravelled).
        if camPos.x.isFinite, camPos.y.isFinite, camPos.z.isFinite {
            if let last = lastCameraPos {
                distanceTravelled += simd_distance(camPos, last)
            }
            lastCameraPos = camPos
        }

        // Project depth samples into world space (skip once the point budget is
        // spent — see maxWorldPoints).
        if worldPoints.count < Self.maxWorldPoints {
            if let depthData = frame.sceneDepth {
                ingestDepthMap(depthData, frame: frame)
            } else if let rawFeatures = frame.rawFeaturePoints {
                // Fallback: project feature points, filtering non-finite ones.
                for pt in rawFeatures.points where pt.x.isFinite && pt.y.isFinite && pt.z.isFinite {
                    worldPoints.append(pt)
                }
            }
        }

        frameCount   += 1
        coverageTracker.ingest(frame)
        let cov = coverageTracker.coverage
        scanProgress    = cov
        instructionText = coverageInstruction(coverage: cov, wallCount: nil)
    }

    func coverageInstruction(coverage: Float, wallCount: Int?) -> String {
        if coverage >= 1.0  { return "Scan complete — tap Done" }
        if coverage >= 0.80 { return "Nearly there — check any corners" }
        if coverage >= 0.60 { return "Look up at the ceiling too" }
        if coverage >= 0.25 {
            if let n = wallCount { return "Good — \(n) wall\(n == 1 ? "" : "s") found, keep sweeping" }
            return "Keep turning — sweep ceiling to floor as you go"
        }
        return "Walk to the centre and turn slowly, sweeping ceiling to floor"
    }

    private func ingestDepthMap(_ depthData: ARDepthData, frame: ARFrame) {
        let buf  = depthData.depthMap
        let w    = CVPixelBufferGetWidth(buf)
        let h    = CVPixelBufferGetHeight(buf)
        CVPixelBufferLockBaseAddress(buf, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buf, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buf) else { return }
        let ptr = base.assumingMemoryBound(to: Float32.self)

        let camIntrinsics = frame.camera.intrinsics   // 3×3 matrix
        let camTransform  = frame.camera.transform    // 4×4 world transform
        // Sample a sparse grid (every 16px) to keep point count manageable
        let step = 16
        let fx = camIntrinsics[0][0], fy = camIntrinsics[1][1]
        let cx = camIntrinsics[2][0], cy = camIntrinsics[2][1]
        // A zero focal length (corrupt intrinsics) would divide-by-zero into Inf.
        guard fx != 0, fy != 0 else { return }
        for row in stride(from: 0, to: h, by: step) {
            for col in stride(from: 0, to: w, by: step) {
                if worldPoints.count >= Self.maxWorldPoints { return }
                let depth = ptr[row * w + col]
                guard depth.isFinite, depth > 0.1, depth < 8.0 else { continue }

                // Back-project pixel to camera space
                let xCam = (Float(col) - cx) / fx * depth
                let yCam = (Float(row) - cy) / fy * depth
                let zCam = depth

                // Transform to world space
                let localPt = SIMD4<Float>(xCam, yCam, -zCam, 1)
                let worldPt = camTransform * localPt
                guard worldPt.x.isFinite, worldPt.y.isFinite, worldPt.z.isFinite else { continue }
                worldPoints.append(SIMD3<Float>(worldPt.x, worldPt.y, worldPt.z))
            }
        }
    }

    private func stopPoseFusion() {
        sweepTimer?.invalidate(); sweepTimer = nil
        let points = worldPoints
        arSession?.pause()
        state = .processing

        Task {
            let result = ScanCoordinator.resultFromPointCloud(points)
            await MainActor.run { self.state = .complete(result) }
        }
    }

    // MARK: - Patch-mode result resolution

    // Pure decision logic (fixture-testable, no RoomPlan types) — see
    // DevToolsChecks.patchResolutionPrefersPassingResult. "Better" = passes
    // the gate; if both or neither pass, prefer more walls (a proxy for
    // "more complete capture"); if still tied, prefer the higher confidence
    // score. Ported from AccuScan's identical ScanSessionManager.shouldPreferNew.
    nonisolated static func shouldPreferNew(
        priorIsPassing: Bool, priorWallCount: Int, priorScore: Float,
        newIsPassing: Bool, newWallCount: Int, newScore: Float
    ) -> Bool {
        if newIsPassing != priorIsPassing { return newIsPassing }
        if newWallCount != priorWallCount { return newWallCount > priorWallCount }
        return newScore >= priorScore
    }

    // MARK: - Dimension extraction: LiDAR

    private static func resultFromLiDAR(_ room: CapturedRoom) -> RoomDimensions {
        let walls   = room.walls
        // Drop any wall with a non-finite/non-positive width so a single degenerate
        // wall can't poison length/width/floorArea with NaN and crash the quote
        // formatter (Int(NaN) traps; JSONSerialization rejects non-finite Doubles).
        let lengths = walls.map { Double($0.dimensions.x) }
                           .filter { $0.isFinite && $0 > 0 }
                           .sorted(by: >)
        let length: Double, width: Double
        switch lengths.count {
        case 4...: length = (lengths[0]+lengths[1])/2; width = (lengths[2]+lengths[3])/2
        case 2...3: length = lengths[0]; width = lengths[1]
        case 1:    length = lengths[0]; width = lengths[0]
        default:   length = 3.0;        width = 2.5
        }
        let rawHeight = walls.first.map { Double($0.dimensions.y) } ?? 2.4
        let height    = (rawHeight.isFinite && rawHeight > 0) ? rawHeight : 2.4
        let floorArea = length * width
        return RoomDimensions(
            length: (length*10).rounded()/10, width: (width*10).rounded()/10,
            height: (height*10).rounded()/10, floorArea: (floorArea*100).rounded()/100,
            wallCount: walls.count, doorCount: room.doors.count, windowCount: room.windows.count,
            roomType: guessRoomType(area: floorArea, windows: room.windows.count),
            scanMethod: .lidar
        )
    }

    // MARK: - Dimension extraction: point cloud bounding box

    private static func resultFromPointCloud(_ points: [SIMD3<Float>]) -> RoomDimensions {
        guard points.count > 50 else { return stubbedResult(method: .poseFusion) }

        // Filter outliers with IQR on each axis
        func iqrFiltered(_ vals: [Float]) -> [Float] {
            let s = vals.sorted()
            let q1 = s[s.count / 4], q3 = s[3 * s.count / 4]
            let iqr = q3 - q1
            return s.filter { $0 >= q1 - 1.5*iqr && $0 <= q3 + 1.5*iqr }
        }

        let xs = iqrFiltered(points.map { $0.x })
        let ys = iqrFiltered(points.map { $0.y })
        let zs = iqrFiltered(points.map { $0.z })

        guard !xs.isEmpty, !ys.isEmpty, !zs.isEmpty else {
            return stubbedResult(method: .poseFusion)
        }

        let xSpan = Double(xs.max()! - xs.min()!)
        let ySpan = Double(ys.max()! - ys.min()!)
        let zSpan = Double(zs.max()! - zs.min()!)

        // X/Z are floor-plane dimensions (horizontal), Y is height
        let dim1   = xSpan.clamped(1.5, 15.0)
        let dim2   = zSpan.clamped(1.5, 15.0)
        let length = max(dim1, dim2).rounded(to: 2)
        let width  = min(dim1, dim2).rounded(to: 2)
        let height = ySpan.clamped(1.8, 5.0).rounded(to: 2)
        let area   = length * width

        return RoomDimensions(
            length: length, width: width, height: height,
            floorArea: (area * 100).rounded() / 100,
            wallCount: 4, doorCount: 1, windowCount: 1,
            roomType: ScanCoordinator.guessRoomType(area: area, windows: 1),
            scanMethod: .poseFusion
        )
    }

    // MARK: - Fallback stub (insufficient data)

    static func stubbedResult(method: ScanMethod) -> RoomDimensions {
        RoomDimensions(
            length: 4.20, width: 3.60, height: 2.40, floorArea: 15.12,
            wallCount: 4, doorCount: 1, windowCount: 2,
            roomType: "living room", scanMethod: method
        )
    }

    // MARK: - Helpers

    private static func guessRoomType(area: Double, windows: Int) -> String {
        switch area {
        case ..<8:    return "bathroom"
        case 8..<12:  return "bedroom"
        case 12..<20: return windows > 1 ? "living room" : "bedroom"
        default:      return "living room"
        }
    }

}

// MARK: - Numeric helpers

extension Double {
    func clamped(_ lo: Double, _ hi: Double) -> Double { max(lo, min(hi, self)) }
    func rounded(to places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}

// MARK: - Scan Error Classifier (Fix #11)
//
// Single shared place for two things every scan-error screen needs and
// previously duplicated or lacked entirely:
//   1. isRetryable — is "Try Again" even meaningful, or is this an error a
//      retry can never fix (needs a subscription, needs sign-in)? Originally
//      only QuoteErrorView had this distinction (Fix #34); ErrorView,
//      SpaceErrorView, and FullWorksErrorView all unconditionally showed
//      "Try Again" regardless of cause.
//   2. friendlyMessage — translates raw ARKit/RoomPlan error strings (e.g.
//      NSError descriptions like "Session was interrupted" or
//      "World tracking failure") into plain-English copy, so
//      ScanCoordinator's catch blocks don't leak framework internals
//      straight into the UI.
enum ScanErrorClassifier {

    static func isRetryable(_ message: String) -> Bool {
        !message.localizedCaseInsensitiveContains("subscription_required") &&
        !message.localizedCaseInsensitiveContains("subscription required") &&
        !message.localizedCaseInsensitiveContains("not authenticated") &&
        !message.localizedCaseInsensitiveContains("sign in")
    }

    /// Maps a raw error description (typically `error.localizedDescription`
    /// from an ARKit/RoomPlan failure) to plain-English copy. Falls through
    /// to a generic message for anything not specifically recognised, rather
    /// than showing the user a framework's internal wording.
    static func friendlyMessage(for rawDescription: String) -> String {
        let lower = rawDescription.lowercased()
        if lower.contains("interrupt") {
            return "Scanning was interrupted. Please try again."
        }
        if lower.contains("tracking") || lower.contains("relocaliz") {
            return "Lost track of the room. Try scanning again in a well-lit space."
        }
        if lower.contains("unsupported") || lower.contains("not supported") || lower.contains("not available") {
            return "This scan type isn't supported on this device."
        }
        if lower.contains("world map") || lower.contains("worldmap") {
            return "Couldn't reconstruct the room. Please try scanning again."
        }
        return "Something went wrong while scanning. Please try again."
    }
}
