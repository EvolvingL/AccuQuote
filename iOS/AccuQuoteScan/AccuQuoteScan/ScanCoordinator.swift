import Foundation
import RoomPlan
import Combine

// MARK: - Scan Result

struct RoomDimensions {
    let length: Double   // longest wall dimension (metres)
    let width: Double    // shortest wall dimension (metres)
    let height: Double   // floor-to-ceiling height (metres)
    let floorArea: Double
    let wallCount: Int
    let doorCount: Int
    let windowCount: Int
    let roomType: String

    var lengthStr: String { String(format: "%.2f", length) }
    var widthStr:  String { String(format: "%.2f", width) }
    var heightStr: String { String(format: "%.2f", height) }

    var returnURL: URL? {
        let baseURL = WEB_APP_BASE_URL
        var components = URLComponents(string: baseURL)
        components?.fragment = "scan-result?length=\(lengthStr)&width=\(widthStr)&height=\(heightStr)&doors=\(doorCount)&windows=\(windowCount)&roomType=\(roomType)"
        return components?.url
    }
}

// MARK: - State

enum ScanState {
    case ready
    case scanning
    case processing
    case complete(RoomDimensions)
    case error(String)
}

// MARK: - Coordinator

// Not @MainActor on the class — NSCoding conformance (inherited from NSObject)
// cannot cross actor boundaries in Swift 6. Instead we dispatch to MainActor
// explicitly inside each method that touches @Published properties.
class ScanCoordinator: NSObject, ObservableObject, RoomCaptureSessionDelegate, RoomCaptureViewDelegate {

    @Published var state: ScanState = .ready
    @Published var instructionText: String = "Slowly move your iPhone around the room"
    @Published var scanProgress: Float = 0.0

    var captureSession: RoomCaptureSession?
    var captureView: RoomCaptureView?

    override init() { super.init() }

    // Explicitly unavailable — we are not an NSCoder-based class.
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    // MARK: - Start / Stop

    @MainActor
    func startScan() {
        guard RoomCaptureSession.isSupported else {
            state = .error("LiDAR not available on this device. RoomPlan requires iPhone 12 Pro or later.")
            return
        }

        let session = RoomCaptureSession()
        captureSession = session
        session.delegate = self

        let view = RoomCaptureView(frame: .zero)
        view.captureSession = session
        view.delegate = self
        captureView = view

        let config = RoomCaptureSession.Configuration()
        session.run(configuration: config)

        state = .scanning
    }

    @MainActor
    func stopScan() {
        captureSession?.stop()
        state = .processing
    }

    @MainActor
    func reset() {
        captureSession?.stop()
        captureSession = nil
        captureView = nil
        state = .ready
        scanProgress = 0
        instructionText = "Slowly move your iPhone around the room"
    }

    // MARK: - RoomCaptureSessionDelegate

    nonisolated func captureSession(_ session: RoomCaptureSession,
                                    didUpdate room: CapturedRoom) {
        let wallCount  = room.walls.count
        let floorCount = room.floors.count
        let progress   = min(Float(wallCount + floorCount) / 6.0, 0.95)

        let instruction: String
        if wallCount == 0 {
            instruction = "Point at the walls to start measuring"
        } else if wallCount < 3 {
            instruction = "Keep moving — scanning more walls"
        } else if floorCount == 0 {
            instruction = "Angle down slightly to capture the floor"
        } else {
            instruction = "Looking good — scan the full room"
        }

        Task { @MainActor in
            self.instructionText = instruction
            self.scanProgress    = progress
        }
    }

    nonisolated func captureSession(_ session: RoomCaptureSession,
                                    didEndWith data: CapturedRoomData,
                                    error: Error?) {
        if let error {
            Task { @MainActor in
                self.state = .error("Scan error: \(error.localizedDescription)")
            }
            return
        }

        Task { @MainActor in
            self.state = .processing
        }

        Task {
            do {
                let builder = RoomBuilder(options: RoomBuilder.Options())
                let room    = try await builder.capturedRoom(from: data)
                let result  = Self.buildResult(from: room)
                await MainActor.run { self.state = .complete(result) }
            } catch {
                await MainActor.run {
                    self.state = .error("Processing failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - RoomCaptureViewDelegate

    nonisolated func captureView(shouldPresent roomDataForProcessing: CapturedRoomData,
                                  error: Error?) -> Bool { true }

    nonisolated func captureView(didPresent processedResult: CapturedRoom, error: Error?) {}

    // MARK: - Process Room (static — no actor isolation needed)

    private static func buildResult(from room: CapturedRoom) -> RoomDimensions {
        let walls  = room.walls
        let floors = room.floors

        var wallLengths: [Double] = walls.map { Double($0.dimensions.x) }
        wallLengths.sort(by: >)

        let length: Double
        let width: Double

        if wallLengths.count >= 4 {
            length = (wallLengths[0] + wallLengths[1]) / 2.0
            width  = (wallLengths[2] + wallLengths[3]) / 2.0
        } else if wallLengths.count >= 2 {
            length = wallLengths[0]
            width  = wallLengths[1]
        } else if wallLengths.count == 1 {
            length = wallLengths[0]
            width  = wallLengths[0]
        } else {
            let floorDims = floors.first.map { (Double($0.dimensions.x), Double($0.dimensions.z)) }
            length = floorDims?.0 ?? 3.0
            width  = floorDims?.1 ?? 2.5
        }

        let height: Double = walls.first.map { Double($0.dimensions.y) } ?? 2.4

        let doorCount   = room.doors.count
        let windowCount = room.windows.count
        let floorArea   = length * width
        let roomType    = guessRoomType(area: floorArea, windows: windowCount)

        return RoomDimensions(
            length:     round(length    * 10)  / 10,
            width:      round(width     * 10)  / 10,
            height:     round(height    * 10)  / 10,
            floorArea:  round(floorArea * 100) / 100,
            wallCount:  walls.count,
            doorCount:  doorCount,
            windowCount: windowCount,
            roomType:   roomType
        )
    }

    private static func guessRoomType(area: Double, windows: Int) -> String {
        switch area {
        case ..<8:    return "bathroom"
        case 8..<12:  return "bedroom"
        case 12..<20: return windows > 1 ? "living room" : "bedroom"
        default:      return "living room"
        }
    }

    // MARK: - Send result back to AccuQuote

    @MainActor
    func sendResultToAccuQuote(result: RoomDimensions) {
        guard let url = result.returnURL else { return }
        UIApplication.shared.open(url, options: [:]) { success in
            if !success {
                UIPasteboard.general.string = "\(result.lengthStr),\(result.widthStr),\(result.heightStr)"
            }
        }
    }
}
