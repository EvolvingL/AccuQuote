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

// NSObject is required for the RoomPlan delegate protocols (Obj-C).
// We cannot put @MainActor on the class itself in Swift 6 because that
// makes NSCoding conformance cross actor boundaries. Instead @MainActor
// is applied per-method where UI updates happen.
class ScanCoordinator: NSObject, ObservableObject {

    @Published var state: ScanState = .ready
    @Published var instructionText: String = "Slowly move your iPhone around the room"
    @Published var scanProgress: Float = 0.0

    private var roomCaptureSession: RoomCaptureSession?
    var captureView: RoomCaptureView?

    override init() { super.init() }

    // MARK: - Start / Stop

    @MainActor
    func startScan() {
        guard RoomCaptureSession.isSupported else {
            state = .error("LiDAR not available on this device. RoomPlan requires iPhone 12 Pro or later.")
            return
        }

        let session = RoomCaptureSession()
        roomCaptureSession = session
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
        roomCaptureSession?.stop()
        state = .processing
    }

    @MainActor
    func reset() {
        roomCaptureSession?.stop()
        roomCaptureSession = nil
        captureView = nil
        state = .ready
        scanProgress = 0
        instructionText = "Slowly move your iPhone around the room"
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

    // MARK: - Process Room (static — no actor isolation needed)

    private static func buildResult(from room: CapturedRoom) -> RoomDimensions {
        let walls = room.walls

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
            // Fallback: derive from wall height aspect ratio
            length = 3.0
            width  = 2.5
        }

        // Height from first wall's Y dimension
        let height: Double = walls.first.map { Double($0.dimensions.y) } ?? 2.4

        let doorCount   = room.doors.count
        let windowCount = room.windows.count
        let floorArea   = length * width
        let roomType    = guessRoomType(area: floorArea, windows: windowCount)

        return RoomDimensions(
            length:      round(length    * 10)  / 10,
            width:       round(width     * 10)  / 10,
            height:      round(height    * 10)  / 10,
            floorArea:   round(floorArea * 100) / 100,
            wallCount:   walls.count,
            doorCount:   doorCount,
            windowCount: windowCount,
            roomType:    roomType
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

// MARK: - RoomCaptureSessionDelegate

extension ScanCoordinator: RoomCaptureSessionDelegate {

    nonisolated func captureSession(_ session: RoomCaptureSession,
                                    didUpdate room: CapturedRoom) {
        let wallCount = room.walls.count
        let progress  = min(Float(wallCount) / 4.0, 0.95)

        let instruction: String
        if wallCount == 0 {
            instruction = "Point at the walls to start measuring"
        } else if wallCount < 3 {
            instruction = "Keep moving — scanning more walls"
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

        Task { @MainActor in self.state = .processing }

        Task {
            do {
                let builder = RoomBuilder(options: [])
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
}

// MARK: - RoomCaptureViewDelegate

extension ScanCoordinator: RoomCaptureViewDelegate {

    nonisolated func captureView(shouldPresent roomDataForProcessing: CapturedRoomData,
                                  error: Error?) -> Bool { true }

    nonisolated func captureView(didPresent processedResult: CapturedRoom,
                                  error: Error?) {}
}
