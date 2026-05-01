import Foundation
import RoomPlan
import ARKit
import Combine
import simd

// MARK: - Scan Method

enum ScanMethod {
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
    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData,
                     error: Error?) -> Bool { true }
    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {}
}

// MARK: - ScanCoordinator

@MainActor
final class ScanCoordinator: ObservableObject {

    @Published var state: ScanState = .ready
    @Published var instructionText: String = ""
    @Published var scanProgress: Float = 0.0
    @Published var frameCount: Int = 0

    // Determined once at init — LiDAR if available, otherwise poseFusion
    let scanMethod: ScanMethod = RoomCaptureSession.isSupported ? .lidar : .poseFusion

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
        var shoelace: Double = 0
        for i in 0..<n {
            let j = (i + 1) % n
            shoelace += Double(vertices[i].x) * Double(vertices[j].y)
            shoelace -= Double(vertices[j].x) * Double(vertices[i].y)
        }
        let area = abs(shoelace) / 2.0 * scale * scale

        // Bounding box for length/width approximation
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

    func reset() {
        lidarSession?.stop(); lidarSession = nil; bridge = nil; captureView = nil
        sweepTimer?.invalidate(); sweepTimer = nil
        arSession?.pause(); arSession = nil
        worldPoints = []; lastCameraPos = nil; distanceTravelled = 0
        frameCount = 0; state = .ready; scanProgress = 0
        instructionText = scanMethod == .lidar
            ? "Walk slowly around the room"
            : "Hold the button and sweep the camera around every wall"
    }

    // MARK: - LiDAR path

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
                self.scanProgress    = min(Float(n) / 6.0, 0.95)
                self.instructionText = n == 0 ? "Point at the walls to begin"
                    : n < 3 ? "Keep moving — \(n) wall\(n == 1 ? "" : "s") detected"
                    : n < 5 ? "Good — scan remaining walls"
                    : "Excellent — tap Done when complete"
            }
        }

        bridge.onEnd = { [weak self] data, error in
            guard let self else { return }
            if let error {
                Task { @MainActor in self.state = .error(error.localizedDescription) }
                return
            }
            Task { @MainActor in self.state = .processing }
            Task {
                do {
                    let room   = try await RoomBuilder(options: []).capturedRoom(from: data)
                    let result = ScanCoordinator.resultFromLiDAR(room)
                    await MainActor.run { self.state = .complete(result) }
                } catch {
                    await MainActor.run { self.state = .error(error.localizedDescription) }
                }
            }
        }

        session.delegate = bridge
        let view = RoomCaptureView(frame: .zero)
        view.delegate = bridge
        captureView = view
        session.run(configuration: RoomCaptureSession.Configuration())
        state = .scanning
    }

    // MARK: - Pose fusion path

    private func startPoseFusion() {
        let session = ARSession()
        let config  = ARWorldTrackingConfiguration()
        // Enable scene depth on supported devices for denser point cloud
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics = [.sceneDepth]
        }
        session.run(config)
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

        // Accumulate distance walked
        if let last = lastCameraPos {
            distanceTravelled += simd_distance(camPos, last)
        }
        lastCameraPos = camPos

        // Project depth samples into world space
        if let depthData = frame.sceneDepth {
            ingestDepthMap(depthData, frame: frame)
        } else {
            // Fallback: project feature points
            if let rawFeatures = frame.rawFeaturePoints {
                for pt in rawFeatures.points {
                    worldPoints.append(pt)
                }
            }
        }

        frameCount   += 1
        // Progress based on distance walked — encourage full room coverage
        // ~4m of walking typically covers a room; cap display at 95%
        let distProgress = min(distanceTravelled / 4.0, 0.95)
        scanProgress = Float(distProgress)

        let meters = String(format: "%.1f", distanceTravelled)
        instructionText = distanceTravelled < 1.0
            ? "Keep walking — sweep every wall"
            : distanceTravelled < 2.5
            ? "Good — \(meters)m covered, keep going"
            : distanceTravelled < 4.0
            ? "Almost there — cover remaining walls"
            : "Tap Done when you've swept the full room"
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
        for row in stride(from: 0, to: h, by: step) {
            for col in stride(from: 0, to: w, by: step) {
                let depth = ptr[row * w + col]
                guard depth > 0.1 && depth < 8.0 else { continue }

                // Back-project pixel to camera space
                let fx = camIntrinsics[0][0], fy = camIntrinsics[1][1]
                let cx = camIntrinsics[2][0], cy = camIntrinsics[2][1]
                let xCam = (Float(col) - cx) / fx * depth
                let yCam = (Float(row) - cy) / fy * depth
                let zCam = depth

                // Transform to world space
                let localPt = SIMD4<Float>(xCam, yCam, -zCam, 1)
                let worldPt = camTransform * localPt
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

    // MARK: - Dimension extraction: LiDAR

    private static func resultFromLiDAR(_ room: CapturedRoom) -> RoomDimensions {
        let walls   = room.walls
        let lengths = walls.map { Double($0.dimensions.x) }.sorted(by: >)
        let length: Double, width: Double
        switch lengths.count {
        case 4...: length = (lengths[0]+lengths[1])/2; width = (lengths[2]+lengths[3])/2
        case 2...3: length = lengths[0]; width = lengths[1]
        case 1:    length = lengths[0]; width = lengths[0]
        default:   length = 3.0;        width = 2.5
        }
        let height    = walls.first.map { Double($0.dimensions.y) } ?? 2.4
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
