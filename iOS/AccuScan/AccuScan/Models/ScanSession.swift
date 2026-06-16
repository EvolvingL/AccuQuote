import Foundation
import CoreData
import RoomPlan
import UIKit

// MARK: - ScanSession
// In-memory model for a completed scan. Wraps the CapturedRoom
// and all metadata. Persisted to CoreData via ScanRecord (NSManagedObject).

struct ScanSession: Identifiable {
    let id: UUID
    var name: String
    var roomType: RoomType
    var date: Date
    var capturedRoom: CapturedRoom
    var scanMethod: ScanMethod
    var deviceInfo: String

    // Derived dimensions
    var wallCount:   Int    { capturedRoom.walls.count }
    var doorCount:   Int    { capturedRoom.doors.count }
    var windowCount: Int    { capturedRoom.windows.count }
    var floorArea:   Double { capturedRoom.floors.first.map { Double($0.dimensions.x * $0.dimensions.z) } ?? estimatedFloorArea }
    var wallArea:    Double {
        capturedRoom.walls.reduce(0.0) { $0 + Double($1.dimensions.x * $1.dimensions.y) }
    }

    // Fall back to bounding-box estimate when no explicit floor
    private var estimatedFloorArea: Double {
        let xs = capturedRoom.walls.map { $0.transform.columns.3.x }
        let zs = capturedRoom.walls.map { $0.transform.columns.3.z }
        guard let xMin = xs.min(), let xMax = xs.max(),
              let zMin = zs.min(), let zMax = zs.max() else { return 0 }
        return Double((xMax - xMin) * (zMax - zMin))
    }

    var ceilingHeight: Double {
        capturedRoom.walls.first.map { Double($0.dimensions.y) } ?? 2.4
    }

    init(id: UUID = UUID(),
         name: String,
         roomType: RoomType,
         date: Date = Date(),
         capturedRoom: CapturedRoom,
         scanMethod: ScanMethod,
         deviceInfo: String = ScanSession.currentDeviceModel) {
        self.id          = id
        self.name        = name
        self.roomType    = roomType
        self.date        = date
        self.capturedRoom = capturedRoom
        self.scanMethod  = scanMethod
        self.deviceInfo  = deviceInfo
    }

    // L4: read the device model off the main actor without touching
    // UIDevice.current (which is MainActor-isolated under strict concurrency and
    // would otherwise make this nonisolated init a data race). uname(2) gives the
    // raw model identifier from any thread.
    nonisolated static var currentDeviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let identifier = mirror.children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(Character(UnicodeScalar(UInt8(value))))
        }
        return identifier.isEmpty ? "iOS device" : identifier
    }
}

// MARK: - RoomType

enum RoomType: String, CaseIterable, Codable {
    case livingRoom    = "Living Room"
    case bedroom       = "Bedroom"
    case kitchen       = "Kitchen"
    case bathroom      = "Bathroom"
    case office        = "Office"
    case hallway       = "Hallway"
    case diningRoom    = "Dining Room"
    case garage        = "Garage"
    case other         = "Other"

    var systemIcon: String {
        switch self {
        case .livingRoom:  return "sofa"
        case .bedroom:     return "bed.double"
        case .kitchen:     return "fork.knife"
        case .bathroom:    return "shower"
        case .office:      return "desktopcomputer"
        case .hallway:     return "arrow.right.to.line"
        case .diningRoom:  return "fork.knife.circle"
        case .garage:      return "car.rear"
        case .other:       return "square"
        }
    }

    // Auto-guess from scan data
    static func guess(floorArea: Double, windowCount: Int) -> RoomType {
        switch floorArea {
        case ..<5:    return .bathroom
        case 5..<10:  return windowCount > 0 ? .bedroom : .bathroom
        case 10..<16: return windowCount > 1 ? .livingRoom : .bedroom
        case 16..<25: return .livingRoom
        default:      return .other
        }
    }
}

// MARK: - ScanMethod

enum ScanMethod: String, Codable {
    case lidar      = "LiDAR"
    case poseFusion = "Camera"
    case manual     = "Manual"

    // Fix #4 — user-facing labels avoid "LiDAR" tech term
    var accuracyLabel: String {
        switch self {
        case .lidar:      return "Precision scan · ±1–2cm"
        case .poseFusion: return "Standard scan · ±5–10cm"
        case .manual:     return "Tape measure"
        }
    }

    var accuracyColourHex: String {
        switch self {
        case .lidar:      return "#22C55E"
        case .poseFusion: return "#3B82F6"
        case .manual:     return "#22C55E"
        }
    }
}

// MARK: - ScanMetadata (lightweight, no CapturedRoom — for home list)

struct ScanMetadata: Identifiable, Codable {
    let id: UUID
    var name: String
    var roomType: RoomType
    var date: Date
    var scanMethod: ScanMethod
    var wallCount: Int
    var doorCount: Int
    var windowCount: Int
    var floorArea: Double
    var wallArea: Double
    var ceilingHeight: Double
    var deviceInfo: String
    // Fix #12 — floor plan thumbnail stored as PNG data
    var thumbnailData: Data?
}
