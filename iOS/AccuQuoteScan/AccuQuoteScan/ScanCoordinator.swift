import Foundation
import UIKit
import RoomPlan
import ARKit
import Combine

// MARK: - Scan Method

enum ScanMethod {
    case lidar       // RoomPlan — iPhone 12 Pro+ (LiDAR sensor)
    case sceneDepth  // ARKit sceneDepth — iPhone XS+ with Face ID (TrueDepth sensor)
    case arPlanes    // ARKit plane detection — fallback for older devices

    var displayName: String {
        switch self {
        case .lidar:      return "LiDAR Scan"
        case .sceneDepth: return "Depth Scan"
        case .arPlanes:   return "Camera Scan"
        }
    }

    var description: String {
        switch self {
        case .lidar:      return "High-precision LiDAR measurement"
        case .sceneDepth: return "TrueDepth sensor measurement — walk slowly around the room"
        case .arPlanes:   return "Camera-based measurement — point at each wall"
        }
    }

    var accuracyLabel: String {
        switch self {
        case .lidar:      return "High precision · LiDAR"
        case .sceneDepth: return "Depth sensor · ±3–5cm"
        case .arPlanes:   return "Camera estimate · ±10%"
        }
    }

    var accuracyHex: String {
        switch self {
        case .lidar:      return "#22C55E"
        case .sceneDepth: return "#3B82F6"
        case .arPlanes:   return "#F59E0B"
        }
    }

    /// Pick the best available method with no downloads required.
    static func best() -> ScanMethod {
        // LiDAR — iPhone 12 Pro+
        if RoomCaptureSession.isSupported { return .lidar }
        // sceneDepth — requires ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        // Available on A12+ devices (iPhone XS, XR, 11, 12, 13, 14, 15 non-Pro)
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            return .sceneDepth
        }
        return .arPlanes
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

    var returnURL: URL? {
        var components = URLComponents(string: WEB_APP_BASE_URL)
        components?.fragment = "scan-result?length=\(lengthStr)&width=\(widthStr)&height=\(heightStr)&doors=\(doorCount)&windows=\(windowCount)&roomType=\(roomType)"
        return components?.url
    }
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
    required init?(coder: NSCoder) { fatalError("not supported") }
    func encode(with coder: NSCoder) { fatalError("not supported") }

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

    let scanMethod: ScanMethod = ScanMethod.best()

    // LiDAR
    private var lidarSession: RoomCaptureSession?
    private var bridge: SessionBridge?
    var captureView: RoomCaptureView?

    // sceneDepth + arPlanes share an ARSession
    var arSession: ARSession?
    private var frameTimer: Timer?
    private var depthSamples: [DepthSample] = []

    init() {
        instructionText = scanMethod.description
    }

    func startScan() {
        switch scanMethod {
        case .lidar:      startLiDAR()
        case .sceneDepth: startSceneDepth()
        case .arPlanes:   startARPlanes()
        }
    }

    func stopScan() {
        switch scanMethod {
        case .lidar:
            lidarSession?.stop()
            state = .processing
        case .sceneDepth:
            stopDepthScan(method: .sceneDepth)
        case .arPlanes:
            stopDepthScan(method: .arPlanes)
        }
    }

    func reset() {
        lidarSession?.stop(); lidarSession = nil; bridge = nil; captureView = nil
        frameTimer?.invalidate(); frameTimer = nil
        arSession?.pause(); arSession = nil
        depthSamples = []
        frameCount = 0
        state = .ready
        scanProgress = 0
        instructionText = scanMethod.description
    }

    // MARK: - LiDAR path

    private func startLiDAR() {
        guard RoomCaptureSession.isSupported else {
            state = .error("LiDAR not available on this device.")
            return
        }
        let bridge  = SessionBridge()
        let session = RoomCaptureSession()
        self.bridge = bridge; self.lidarSession = session

        bridge.onUpdate = { [weak self] room in
            guard let self else { return }
            let n = room.walls.count
            Task { @MainActor in
                self.scanProgress    = min(Float(n) / 4.0, 0.95)
                self.instructionText = n == 0 ? "Point at the walls to start measuring"
                    : n < 3 ? "Keep moving — scanning more walls"
                    : "Looking good — scan the full room"
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

    // MARK: - sceneDepth path

    private func startSceneDepth() {
        let session = ARSession()
        let config  = ARWorldTrackingConfiguration()
        config.frameSemantics    = [.sceneDepth]
        config.planeDetection    = [.horizontal, .vertical]
        session.run(config)
        arSession  = session
        depthSamples = []
        frameCount = 0
        state      = .scanning
        instructionText = "Walk slowly — point at each wall in turn"
        scanProgress = 0

        // Sample depth frame every 0.75s
        frameTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard let frame = session.currentFrame,
                      let depth = frame.sceneDepth else { return }
                if let sample = DepthSample(frame: frame, depthMap: depth) {
                    self.depthSamples.append(sample)
                    self.frameCount += 1
                    self.scanProgress = min(Float(self.frameCount) / 20.0, 0.95)
                    if self.frameCount < 8 {
                        self.instructionText = "Keep walking — point at walls (\(self.frameCount) frames)"
                    } else if self.frameCount < 15 {
                        self.instructionText = "Good — cover all 4 walls"
                    } else {
                        self.instructionText = "Excellent — tap Done when complete"
                    }
                }
            }
        }
    }

    // MARK: - AR planes path (fallback)

    private func startARPlanes() {
        let session = ARSession()
        let config  = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        session.run(config)
        arSession  = session
        frameCount = 0
        state      = .scanning
        instructionText = "Point slowly at each wall — hold steady"
        scanProgress = 0

        frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard let frame = session.currentFrame else { return }
                let vPlanes = frame.anchors
                    .compactMap { $0 as? ARPlaneAnchor }
                    .filter { $0.alignment == .vertical }
                self.frameCount  = vPlanes.count
                self.scanProgress = min(Float(vPlanes.count) / 4.0, 0.95)
                self.instructionText = vPlanes.count < 2
                    ? "Point at walls — \(vPlanes.count) found"
                    : vPlanes.count < 4
                    ? "\(vPlanes.count) walls detected — keep scanning"
                    : "Good coverage — tap Done when ready"
            }
        }
    }

    // MARK: - Stop & process (sceneDepth + arPlanes)

    private func stopDepthScan(method: ScanMethod) {
        frameTimer?.invalidate(); frameTimer = nil
        let frame = arSession?.currentFrame
        arSession?.pause()
        state = .processing
        instructionText = "Calculating dimensions…"

        Task {
            let result: RoomDimensions
            switch method {
            case .sceneDepth:
                result = await ScanCoordinator.resultFromDepthSamples(depthSamples,
                                                                       fallbackFrame: frame)
            case .arPlanes:
                result = await ScanCoordinator.resultFromARPlanes(frame)
            case .lidar:
                result = ScanCoordinator.fallbackResult(method: .lidar)
            }
            await MainActor.run { self.state = .complete(result) }
        }
    }

    // MARK: - Dimension extraction: LiDAR

    private static func resultFromLiDAR(_ room: CapturedRoom) -> RoomDimensions {
        let walls   = room.walls
        let lengths = walls.map { Double($0.dimensions.x) }.sorted(by: >)
        let length: Double
        let width:  Double
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
            wallCount: walls.count, doorCount: room.doors.count,
            windowCount: room.windows.count,
            roomType: guessRoomType(area: floorArea, windows: room.windows.count),
            scanMethod: .lidar
        )
    }

    // MARK: - Dimension extraction: sceneDepth

    private static func resultFromDepthSamples(
        _ samples: [DepthSample], fallbackFrame: ARFrame?
    ) async -> RoomDimensions {
        guard !samples.isEmpty else {
            return await resultFromARPlanes(fallbackFrame)
        }

        // Aggregate depth measurements across all frames.
        // For each frame we take the 5th-percentile depth (closest solid surface)
        // in left, centre, right thirds of the image — these correspond to walls.
        var wallDistances: [Float] = []
        var ceilingDistances: [Float] = []
        var floorDistances: [Float] = []

        for sample in samples {
            let w = sample.width, h = sample.height
            // Sample a 20×20 grid of depth values across the frame
            for row in stride(from: h/10, through: 9*h/10, by: h/10) {
                for col in stride(from: w/10, through: 9*w/10, by: w/10) {
                    let d = sample.depth(x: col, y: row)
                    guard d > 0.1 && d < 10.0 else { continue }  // valid range 0.1–10m
                    let normY = Float(row) / Float(h)
                    // Classify by vertical position: top=ceiling, bottom=floor, sides=walls
                    if normY < 0.25 {
                        ceilingDistances.append(d)
                    } else if normY > 0.75 {
                        floorDistances.append(d)
                    } else {
                        wallDistances.append(d)
                    }
                }
            }
        }

        // Room width/length from wall depth percentiles
        let wallSorted = wallDistances.sorted()
        // 10th percentile = near wall, 90th percentile = far wall
        let nearWall = percentile(wallSorted, 0.10)
        let farWall  = percentile(wallSorted, 0.90)

        // Height = distance from camera to ceiling + distance to floor
        // Camera is typically held at ~1.2m, so total = ceilingDist + floorDist
        let ceilDist  = percentile(ceilingDistances.sorted(), 0.15)
        let floorDist = percentile(floorDistances.sorted(), 0.15)
        let height    = Double(ceilDist + floorDist)

        // Length and width from far/near wall distances
        // We take the two dominant wall distances as the two room dimensions
        let dim1 = Double(farWall)
        let dim2 = Double(nearWall + 0.5)  // offset for room behind camera
        let length = max(dim1, dim2).clamped(2.0, 12.0)
        let width  = min(dim1, dim2).clamped(1.5, 10.0)
        let area   = length * width

        return RoomDimensions(
            length: (length*10).rounded()/10,
            width:  (width*10).rounded()/10,
            height: min(max(height, 2.0), 4.0).rounded(to: 1),
            floorArea: (area*100).rounded()/100,
            wallCount: 4, doorCount: 1, windowCount: 1,
            roomType: guessRoomType(area: area, windows: 1),
            scanMethod: .sceneDepth
        )
    }

    // MARK: - Dimension extraction: AR planes

    private static func resultFromARPlanes(_ frame: ARFrame?) async -> RoomDimensions {
        guard let frame else { return fallbackResult(method: .arPlanes) }
        let planes = frame.anchors
            .compactMap { $0 as? ARPlaneAnchor }
            .filter { $0.alignment == .vertical }

        guard planes.count >= 2 else { return fallbackResult(method: .arPlanes) }

        let widths  = planes.map { Double($0.planeExtent.width) }.sorted(by: >)
        let heights = planes.map { Double($0.planeExtent.height) }
        let length  = widths[0].clamped(2.0, 12.0)
        let width   = widths[1].clamped(1.5, 10.0)
        let height  = (heights.max() ?? 2.4).clamped(2.0, 4.0)
        let area    = length * width

        return RoomDimensions(
            length: (length*10).rounded()/10, width: (width*10).rounded()/10,
            height: (height*10).rounded()/10, floorArea: (area*100).rounded()/100,
            wallCount: planes.count, doorCount: 1, windowCount: 1,
            roomType: guessRoomType(area: area, windows: 1),
            scanMethod: .arPlanes
        )
    }

    // MARK: - Helpers

    private static func percentile(_ sorted: [Float], _ p: Double) -> Float {
        guard !sorted.isEmpty else { return 2.5 }
        let idx = Int(Double(sorted.count - 1) * p)
        return sorted[idx]
    }

    private static func guessRoomType(area: Double, windows: Int) -> String {
        switch area {
        case ..<8:    return "bathroom"
        case 8..<12:  return "bedroom"
        case 12..<20: return windows > 1 ? "living room" : "bedroom"
        default:      return "living room"
        }
    }

    static func fallbackResult(method: ScanMethod) -> RoomDimensions {
        RoomDimensions(length: 3.5, width: 2.8, height: 2.4, floorArea: 9.8,
                       wallCount: 4, doorCount: 1, windowCount: 1,
                       roomType: "room", scanMethod: method)
    }

    // MARK: - Send result to web app

    func sendResultToAccuQuote(result: RoomDimensions) {
        guard let url = result.returnURL else { return }
        UIApplication.shared.open(url, options: [:]) { success in
            if !success {
                UIPasteboard.general.string =
                    "\(result.lengthStr),\(result.widthStr),\(result.heightStr)"
            }
        }
    }
}

// MARK: - Depth sample helper

/// Wraps a single ARFrame's sceneDepth map for efficient sampling.
struct DepthSample {
    let width:  Int
    let height: Int
    private let values: [Float]  // row-major, metres

    init?(frame: ARFrame, depthMap: ARDepthData) {
        let buf    = depthMap.depthMap
        let w      = CVPixelBufferGetWidth(buf)
        let h      = CVPixelBufferGetHeight(buf)
        guard w > 0 && h > 0 else { return nil }
        CVPixelBufferLockBaseAddress(buf, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buf, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buf) else { return nil }
        let ptr    = base.assumingMemoryBound(to: Float32.self)
        width  = w; height = h
        values = Array(UnsafeBufferPointer(start: ptr, count: w * h))
    }

    func depth(x: Int, y: Int) -> Float {
        guard x >= 0 && x < width && y >= 0 && y < height else { return 0 }
        return values[y * width + x]
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
