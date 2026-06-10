import RoomPlan
import ARKit
import Combine
import simd

// MARK: - ScanSessionManager
// Central coordinator between RoomPlan, WallCoverageTracker, and all UI.
// All state mutations happen on the MainActor. Delegate methods are nonisolated
// (called on RoomPlan/ARKit background queues) and hop back via Task { @MainActor in }.

@MainActor
final class ScanSessionManager: NSObject, ObservableObject {

    // MARK: - Published state (drives all UI)
    @Published var scanState: ScanState = .idle
    @Published var capturedRoom: CapturedRoom?
    @Published var walls: [TrackedWall] = []
    @Published var overallCoverage: Float = 0.0
    @Published var instructionText: String = "Move slowly around the room"
    @Published var errorMessage: String?
    @Published var isInterrupted: Bool = false
    @Published var isCoachingActive: Bool = false   // driven by ARCoachingOverlayViewDelegate

    // MARK: - RoomPlan objects
    private(set) var captureView: RoomCaptureView?
    private var captureSession: RoomCaptureSession?
    private let wallTracker = WallCoverageTracker()

    // Coverage ring — mirrors AccuQuote's Face-ID-style scan ring
    let coverageTracker = ScanCoverageTracker()

    // Tracks last wall count so haptics only fire on new wall detections, not every tick
    private var lastHapticWallCount = 0

    // MARK: - Capabilities
    static var supportsLiDAR: Bool { RoomCaptureSession.isSupported }

    // MARK: - Scan State

    enum ScanState: Equatable {
        case idle
        case preparing
        case scanning
        case processing
        case complete(CapturedRoom)
        case error(String)

        static func == (lhs: ScanState, rhs: ScanState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.preparing, .preparing), (.scanning, .scanning),
                 (.processing, .processing): return true
            case (.complete, .complete): return true
            case (.error(let a), .error(let b)): return a == b
            default: return false
            }
        }

        var tag: Int {
            switch self {
            case .idle: return 0; case .preparing: return 1; case .scanning: return 2
            case .processing: return 3; case .complete: return 4; case .error: return 5
            }
        }
    }

    // MARK: - Setup

    func makeRoomCaptureView() -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero)
        view.captureSession.delegate = self
        view.delegate = self
        // Wire ARSessionDelegate so interruption/error callbacks are received
        view.captureSession.arSession.delegate = self
        self.captureView = view
        self.captureSession = view.captureSession
        return view
    }

    // MARK: - Controls

    func startScan() {
        // H5: re-entrancy guard. viewDidAppear can fire more than once (e.g. a sheet
        // dismissed over the scan view); starting again would restart RoomPlan and
        // discard partial scan data. Only begin a scan from idle/error/preparing.
        if case .scanning = scanState { return }
        if case .processing = scanState { return }

        wallTracker.reset()
        coverageTracker.reset()
        walls = []
        overallCoverage = 0
        errorMessage = nil
        isInterrupted = false
        lastHapticWallCount = 0

        guard Self.supportsLiDAR else {
            scanState = .error("This scan requires an iPhone 12 Pro or later.")
            return
        }
        startLiDAR()
    }

    /// Restart capture on the existing session without tearing down the capture view.
    /// Used by the coaching "Start Over" path — a full reset() nils the session and
    /// the view, after which run() is a silent no-op and the scan freezes (H4).
    func restartScan() {
        guard captureSession != nil else { return }
        wallTracker.reset()
        coverageTracker.reset()
        walls = []
        overallCoverage = 0
        lastHapticWallCount = 0
        isInterrupted = false
        startLiDAR()
    }

    func stopScan() {
        captureSession?.stop()
        scanState = .processing
    }

    func pauseScan() {
        // RoomCaptureSession has no native pause — stopping loses partial data.
        // We warn the user via the UI before they tap pause. Here we stop and
        // reset so that resumeScan() starts fresh without stale state.
        wallTracker.reset()
        walls = []
        overallCoverage = 0
        lastHapticWallCount = 0
        captureSession?.stop()
    }

    func resumeScan() {
        guard Self.supportsLiDAR else { return }
        let config = RoomCaptureSession.Configuration()
        captureSession?.run(configuration: config)
        scanState = .scanning
        instructionText = "Walk slowly around the room"
    }

    // Called when the view disappears — stops the session synchronously to
    // prevent in-flight delegate callbacks from arriving after reset().
    func stopCapture() {
        captureSession?.arSession.delegate = nil
        captureSession?.stop()
    }

    func reset() {
        // Clear delegate first to cut off any in-flight callbacks
        captureSession?.arSession.delegate = nil
        captureSession?.stop()
        captureSession = nil
        captureView = nil
        wallTracker.reset()
        coverageTracker.reset()
        walls = []
        overallCoverage = 0
        capturedRoom = nil
        scanState = .idle
        isInterrupted = false
        isCoachingActive = false
        lastHapticWallCount = 0
        instructionText = "Move slowly around the room"
        errorMessage = nil
    }

    // MARK: - LiDAR

    private func startLiDAR() {
        // H4: if the session was torn down, don't silently no-op into a frozen
        // "scanning" state — surface an error the user can recover from.
        guard let session = captureSession else {
            scanState = .error("Scanner not ready. Tap Try again to restart.")
            return
        }
        session.run(configuration: RoomCaptureSession.Configuration())
        scanState = .scanning
        instructionText = "Walk slowly around the room"
    }
}

// MARK: - RoomCaptureSessionDelegate

extension ScanSessionManager: RoomCaptureSessionDelegate {

    nonisolated func captureSession(_ session: RoomCaptureSession,
                                    didUpdate room: CapturedRoom) {
        // Feed ARSession frames into the coverage tracker for the ring UI.
        // This mirrors AccuQuote's approach of sampling frames alongside RoomPlan updates.
        if let frame = session.arSession.currentFrame {
            Task { @MainActor in self.coverageTracker.ingest(frame) }
        }

        let wallCount = room.walls.count
        Task { @MainActor in
            let newWalls = self.wallTracker.update(from: room)
            let coverage = self.wallTracker.calculateOverallCoverage()

            // Only fire haptic when a new wall is detected, not on every sensor tick
            if newWalls.count > self.lastHapticWallCount {
                HapticService.shared.selection()
                self.lastHapticWallCount = newWalls.count
            }

            self.walls = newWalls
            self.overallCoverage = coverage
            self.instructionText = wallCount < 3
                ? "Move slowly around the whole room"
                : wallCount < 5
                    ? "Good — scan the remaining walls"
                    : "Excellent — tap Done when complete"
        }
    }

    nonisolated func captureSession(_ session: RoomCaptureSession,
                                    didProvide instruction: RoomCaptureSession.Instruction) {
        let text: String
        switch instruction {
        case .moveCloseToWall:  text = "Move closer to the walls"
        case .moveAwayFromWall: text = "Step back a little"
        case .slowDown:         text = "Slow down — keep it steady"
        case .turnOnLight:      text = "More light needed — turn on a light or open a blind"
        case .normal:           text = "Keep going…"
        default:                text = "Keep going…"
        }
        Task { @MainActor in self.instructionText = text }
    }
}

// MARK: - RoomCaptureViewDelegate

extension ScanSessionManager: RoomCaptureViewDelegate {

    nonisolated func captureView(shouldPresent roomDataForProcessing: CapturedRoomData,
                                 error: Error?) -> Bool {
        return error == nil
    }

    nonisolated func captureView(didPresent processedResult: CapturedRoom,
                                 error: Error?) {
        if let error {
            Task { @MainActor in self.scanState = .error(error.localizedDescription) }
            return
        }
        // C4/H1: reject an empty room. RoomPlan will happily return a CapturedRoom
        // with zero walls if the user taps Done immediately. An empty room produces
        // a 0 floor area downstream (and a divide-by-zero in any per-m² maths), so
        // surface a clear error instead of completing with unusable geometry.
        guard !processedResult.walls.isEmpty else {
            Task { @MainActor in
                self.scanState = .error("No walls detected. Move around the room and try again.")
            }
            return
        }
        Task { @MainActor in
            self.capturedRoom = processedResult
            self.walls        = self.wallTracker.update(from: processedResult)
            self.scanState    = .complete(processedResult)
            HapticService.shared.success()
        }
    }
}

// MARK: - ARSessionDelegate (superset of ARSessionObserver — required for delegate assignment)

extension ScanSessionManager: ARSessionDelegate {

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor in
            self.isInterrupted   = true
            self.instructionText = "Scan paused — return to resume"
            HapticService.shared.warning()
        }
    }

    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        Task { @MainActor in
            self.isInterrupted   = false
            self.instructionText = "Resuming…"
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.scanState = .error(error.localizedDescription)
        }
    }
}
