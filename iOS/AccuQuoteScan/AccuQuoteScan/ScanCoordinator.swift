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
    let roomType: String // best-guess from dimensions

    var lengthStr: String { String(format: "%.2f", length) }
    var widthStr:  String { String(format: "%.2f", width) }
    var heightStr: String { String(format: "%.2f", height) }

    /// URL that returns to the AccuQuote web app with scan results embedded in the hash.
    /// Works whether the app is running on localhost or a live domain.
    /// The web app listens for #scan-result?... on hashchange.
    ///
    /// UPDATE baseURL below to match your live domain once deployed.
    var returnURL: URL? {
        // ── Change this to your live domain when deployed ──
        let baseURL = "http://localhost:3000"
        // ──────────────────────────────────────────────────

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

@MainActor
class ScanCoordinator: NSObject, ObservableObject, RoomCaptureSessionDelegate, RoomCaptureViewDelegate {

    @Published var state: ScanState = .ready
    @Published var instructionText: String = "Slowly move your iPhone around the room"
    @Published var scanProgress: Float = 0.0

    var captureSession: RoomCaptureSession?
    var captureView: RoomCaptureView?

    // MARK: - Start / Stop

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

    func stopScan() {
        captureSession?.stop()
        state = .processing
    }

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
        Task { @MainActor in
            // Update instruction based on what's been found
            let wallCount = room.walls.count
            let floorCount = room.floors.count
            if wallCount == 0 {
                instructionText = "Point at the walls to start measuring"
            } else if wallCount < 3 {
                instructionText = "Keep moving — scanning more walls"
            } else if floorCount == 0 {
                instructionText = "Angle down slightly to capture the floor"
            } else {
                instructionText = "Looking good — scan the full room"
            }
            // Rough progress: 4 walls + floor + ceiling = ~6 surfaces
            scanProgress = min(Float(wallCount + floorCount) / 6.0, 0.95)
        }
    }

    nonisolated func captureSession(_ session: RoomCaptureSession,
                                    didEndWith data: CapturedRoomData,
                                    error: Error?) {
        if let error {
            Task { @MainActor in
                state = .error("Scan error: \(error.localizedDescription)")
            }
            return
        }

        // Process the raw data into a final CapturedRoom
        Task { @MainActor in
            state = .processing
        }

        let request = RoomBuilder.Options()
        Task {
            do {
                let builder = RoomBuilder(options: request)
                let room = try await builder.capturedRoom(from: data)
                await MainActor.run {
                    self.processFinalRoom(room)
                }
            } catch {
                await MainActor.run {
                    state = .error("Processing failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - RoomCaptureViewDelegate

    nonisolated func captureView(shouldPresent roomDataForProcessing: CapturedRoomData,
                                  error: Error?) -> Bool {
        return true // let the session delegate handle it
    }

    nonisolated func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        // handled by captureSession didEndWith
    }

    // MARK: - Process Room

    private func processFinalRoom(_ room: CapturedRoom) {
        // Extract wall dimensions
        let walls = room.walls
        let floors = room.floors

        // Get unique wall lengths (RoomPlan gives each wall surface)
        // We want the overall bounding box of the room
        var wallLengths: [Double] = walls.map { Double($0.dimensions.x) }
        wallLengths.sort(by: >)

        // Best estimate: longest pair = length, next pair = width
        let length: Double
        let width: Double

        if wallLengths.count >= 4 {
            // Average the two longest for length, next two for width
            length = (wallLengths[0] + wallLengths[1]) / 2.0
            width  = (wallLengths[2] + wallLengths[3]) / 2.0
        } else if wallLengths.count >= 2 {
            length = wallLengths[0]
            width  = wallLengths[1]
        } else if wallLengths.count == 1 {
            length = wallLengths[0]
            width  = wallLengths[0]
        } else {
            // Fallback: use floor bounding box
            let floorDims = floors.first.map { (Double($0.dimensions.x), Double($0.dimensions.z)) }
            length = floorDims?.0 ?? 3.0
            width  = floorDims?.1 ?? 2.5
        }

        // Height: use floor-to-ceiling from floor surface height + wall height
        let height: Double
        if let wall = walls.first {
            height = Double(wall.dimensions.y)
        } else {
            height = 2.4 // standard UK ceiling
        }

        let floorArea = length * width

        // Count openings
        let doorCount   = room.doors.count
        let windowCount = room.windows.count

        // Guess room type from dimensions
        let roomType = guessRoomType(area: floorArea, doors: doorCount, windows: windowCount)

        let result = RoomDimensions(
            length: round(length * 10) / 10,
            width:  round(width  * 10) / 10,
            height: round(height * 10) / 10,
            floorArea: round(floorArea * 100) / 100,
            wallCount: walls.count,
            doorCount: doorCount,
            windowCount: windowCount,
            roomType: roomType
        )

        state = .complete(result)
    }

    private func guessRoomType(area: Double, doors: Int, windows: Int) -> String {
        switch area {
        case ..<4:    return "bathroom"
        case 4..<8:   return "bathroom"
        case 8..<12:  return "bedroom"
        case 12..<20: return windows > 1 ? "living room" : "bedroom"
        default:      return "living room"
        }
    }

    // MARK: - Send result back to AccuQuote

    func sendResultToAccuQuote(result: RoomDimensions) {
        guard let url = result.returnURL else { return }
        // Open the AccuQuote web app (running in Safari / WKWebView)
        UIApplication.shared.open(url, options: [:]) { success in
            if !success {
                // Web app not open — copy to clipboard as fallback
                UIPasteboard.general.string = "\(result.lengthStr),\(result.widthStr),\(result.heightStr)"
            }
        }
    }
}
