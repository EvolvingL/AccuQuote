import Foundation
import UIKit
import RoomPlan
import Combine

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

    var lengthStr: String { String(format: "%.2f", length) }
    var widthStr:  String { String(format: "%.2f", width) }
    var heightStr: String { String(format: "%.2f", height) }

    var returnURL: URL? {
        var components = URLComponents(string: WEB_APP_BASE_URL)
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

// MARK: - Delegate bridge
// A minimal NSObject that satisfies the Obj-C delegate protocols and
// forwards events to ScanCoordinator via closures. This keeps
// ScanCoordinator free of NSObject / NSCoding entirely.

@objc(AQSessionBridge)
private final class SessionBridge: NSObject, RoomCaptureSessionDelegate, RoomCaptureViewDelegate {

    var onUpdate:  ((CapturedRoom) -> Void)?
    var onEnd:     ((CapturedRoomData, Error?) -> Void)?

    override init() { super.init() }
    required init?(coder: NSCoder) { fatalError("not supported") }
    func encode(with coder: NSCoder) { fatalError("not supported") }

    // RoomCaptureSessionDelegate
    func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        onUpdate?(room)
    }

    func captureSession(_ session: RoomCaptureSession,
                        didEndWith data: CapturedRoomData, error: Error?) {
        onEnd?(data, error)
    }

    // RoomCaptureViewDelegate
    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData,
                     error: Error?) -> Bool { true }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {}
}

// MARK: - Coordinator
// Plain Swift class — no NSObject, no NSCoding, no actor conflicts.

@MainActor
final class ScanCoordinator: ObservableObject {

    @Published var state: ScanState = .ready
    @Published var instructionText: String = "Slowly move your iPhone around the room"
    @Published var scanProgress: Float = 0.0

    private var session: RoomCaptureSession?
    private var bridge:  SessionBridge?
    var captureView: RoomCaptureView?

    // MARK: - Start / Stop

    func startScan() {
        guard RoomCaptureSession.isSupported else {
            state = .error("LiDAR not available. RoomPlan requires iPhone 12 Pro or later.")
            return
        }

        let bridge   = SessionBridge()
        let session  = RoomCaptureSession()
        self.bridge  = bridge
        self.session = session

        // Wire callbacks
        bridge.onUpdate = { [weak self] room in
            guard let self else { return }
            let wallCount = room.walls.count
            let progress  = min(Float(wallCount) / 4.0, 0.95)
            let text: String
            if wallCount == 0      { text = "Point at the walls to start measuring" }
            else if wallCount < 3  { text = "Keep moving — scanning more walls" }
            else                   { text = "Looking good — scan the full room" }
            Task { @MainActor in
                self.instructionText = text
                self.scanProgress    = progress
            }
        }

        bridge.onEnd = { [weak self] data, error in
            guard let self else { return }
            if let error {
                Task { @MainActor in self.state = .error("Scan error: \(error.localizedDescription)") }
                return
            }
            Task { @MainActor in self.state = .processing }
            Task {
                do {
                    let builder = RoomBuilder(options: [])
                    let room    = try await builder.capturedRoom(from: data)
                    let result  = ScanCoordinator.buildResult(from: room)
                    await MainActor.run { self.state = .complete(result) }
                } catch {
                    await MainActor.run {
                        self.state = .error("Processing failed: \(error.localizedDescription)")
                    }
                }
            }
        }

        session.delegate = bridge

        // Build the capture view and attach the session
        let view = RoomCaptureView(frame: .zero)
        view.delegate = bridge
        self.captureView = view

        session.run(configuration: RoomCaptureSession.Configuration())
        state = .scanning
    }

    func stopScan() {
        session?.stop()
        state = .processing
    }

    func reset() {
        session?.stop()
        session     = nil
        bridge      = nil
        captureView = nil
        state       = .ready
        scanProgress    = 0
        instructionText = "Slowly move your iPhone around the room"
    }

    func sendResultToAccuQuote(result: RoomDimensions) {
        guard let url = result.returnURL else { return }
        UIApplication.shared.open(url, options: [:]) { success in
            if !success {
                UIPasteboard.general.string = "\(result.lengthStr),\(result.widthStr),\(result.heightStr)"
            }
        }
    }

    // MARK: - Process room (static, no actor isolation needed)

    private static func buildResult(from room: CapturedRoom) -> RoomDimensions {
        let walls = room.walls
        var lengths = walls.map { Double($0.dimensions.x) }.sorted(by: >)

        let length: Double
        let width: Double

        switch lengths.count {
        case 4...: length = (lengths[0] + lengths[1]) / 2; width = (lengths[2] + lengths[3]) / 2
        case 2...3: length = lengths[0]; width = lengths[1]
        case 1:     length = lengths[0]; width = lengths[0]
        default:    length = 3.0;        width = 2.5
        }

        let height    = walls.first.map { Double($0.dimensions.y) } ?? 2.4
        let floorArea = length * width

        return RoomDimensions(
            length:      (length    * 10).rounded()  / 10,
            width:       (width     * 10).rounded()  / 10,
            height:      (height    * 10).rounded()  / 10,
            floorArea:   (floorArea * 100).rounded() / 100,
            wallCount:   walls.count,
            doorCount:   room.doors.count,
            windowCount: room.windows.count,
            roomType:    guessRoomType(area: floorArea, windows: room.windows.count)
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
}
