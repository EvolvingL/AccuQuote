import Foundation
import RoomPlan
import Combine

// MARK: - FullWorksSession (Tri-Mode Scanning build spec §4.1)
//
// iOS 17+ only — StructureBuilder (the multi-room merge API this whole mode
// depends on) doesn't exist on iOS 16. Callers must guard with
// FullWorksSession.isSupported and hide the Full Works card entirely
// otherwise (§4.1: "On iOS 16, hide the card.").
//
// Deliberately wraps ScanCoordinator's existing Room engine per room rather
// than forking a second capture pipeline (§4.1: "do not fork it") — each
// room in a floor is captured exactly the way a standalone Room-mode scan
// is, this class just orchestrates "scan room → keep the CapturedRoom →
// prompt for the next room → repeat → merge" around that existing engine.

struct Floor: Identifiable {
    let id: String
    var label: String
    var rooms: [CapturedRoomRecord]

    init(id: String = UUID().uuidString, label: String, rooms: [CapturedRoomRecord] = []) {
        self.id = id
        self.label = label
        self.rooms = rooms
    }
}

struct CapturedRoomRecord: Identifiable {
    let id: String
    var name: String
    let room: CapturedRoom
    let dimensions: RoomDimensions

    init(id: String = UUID().uuidString, name: String, room: CapturedRoom, dimensions: RoomDimensions) {
        self.id = id
        self.name = name
        self.room = room
        self.dimensions = dimensions
    }
}

enum FullWorksPhase {
    case setup            // naming the property, picking the first floor
    case scanningRoom     // live Room-engine scan in progress
    case betweenRooms     // floor summary shown, prompting for next room or finish
    case merging          // StructureBuilder running
    case complete
    case error(String)
}

@MainActor
final class FullWorksSession: ObservableObject {

    @Published var propertyName: String = ""
    @Published var floors: [Floor] = []
    @Published var currentFloorIndex: Int = 0
    // didSet mirrors ScanCoordinator/SpaceCaptureCoordinator's pattern —
    // every phase assignment updates ScanStorageManager's scan-in-progress
    // guard automatically. .scanningRoom is the live per-room capture;
    // .merging runs StructureBuilder over already-captured per-room data
    // (no live sensor writes, but still reading/writing scan artifacts on
    // disk under aq_scans/, so it's treated as "in progress" too).
    @Published var phase: FullWorksPhase = .setup {
        didSet {
            switch phase {
            case .scanningRoom, .merging:
                ScanStorageManager.isScanInProgress = true
            case .setup, .betweenRooms, .complete, .error:
                ScanStorageManager.isScanInProgress = false
            }
        }
    }

    /// Merged per-floor structures, keyed by Floor.id, populated during
    /// .merging. §4.1: "Whole-house = array of per-floor structures stacked
    /// with floor-height offsets" — the stacking/offset math lives in
    /// FullWorksOutput, this just holds the raw merge results.
    ///
    /// Stored as `Any` rather than `[String: CapturedStructure]` — a stored
    /// property's type can't be gated behind `@available` while the class
    /// itself must support the app's iOS 16 deployment target (isSupported
    /// already keeps this whole session iOS-17-only in practice; this is
    /// purely to satisfy the compiler that the class DECLARATION is valid on
    /// iOS 16, even though nothing on iOS 16 will ever populate this dict).
    @Published private var mergedStructuresStorage: [String: Any] = [:]

    @available(iOS 17.0, *)
    var mergedStructures: [String: CapturedStructure] {
        get { mergedStructuresStorage.compactMapValues { $0 as? CapturedStructure } }
        set { mergedStructuresStorage = newValue }
    }

    /// Wall-clock scan duration for the completion stat card (§4.2
    /// "screenshot-bait": "Scanned a 4-bed in 14 minutes").
    private var scanStartedAt: Date?

    static var isSupported: Bool {
        if #available(iOS 17.0, *) { return true }
        return false
    }

    var currentFloor: Floor? {
        guard floors.indices.contains(currentFloorIndex) else { return nil }
        return floors[currentFloorIndex]
    }

    var totalRoomCount: Int { floors.reduce(0) { $0 + $1.rooms.count } }

    var totalFloorAreaSqMetres: Double {
        floors.flatMap { $0.rooms }.reduce(0) { $0 + $1.dimensions.floorArea }
    }

    // MARK: - Setup

    func start(propertyName: String, firstFloorLabel: String) {
        self.propertyName = propertyName
        floors = [Floor(label: firstFloorLabel)]
        currentFloorIndex = 0
        phase = .setup
        scanStartedAt = Date()
    }

    func addFloor(label: String) {
        floors.append(Floor(label: label))
        currentFloorIndex = floors.count - 1
        phase = .betweenRooms
    }

    // MARK: - Per-room capture

    /// Called once ScanCoordinator's Room engine reaches a passing .complete
    /// (or a warnings-accepted one) for the room the user just scanned —
    /// same acceptance rule Room mode itself uses, so Full Works never
    /// accumulates a room that wouldn't have passed on its own.
    func recordCompletedRoom(_ room: CapturedRoom, dimensions: RoomDimensions, name: String? = nil) {
        guard floors.indices.contains(currentFloorIndex) else { return }
        let roomName = name ?? "Room \(floors[currentFloorIndex].rooms.count + 1)"
        let record = CapturedRoomRecord(name: roomName, room: room, dimensions: dimensions)
        floors[currentFloorIndex].rooms.append(record)
        phase = .betweenRooms
    }

    func beginScanningNextRoom() {
        phase = .scanningRoom
    }

    /// §4.1 "Finish floor" — either moves to the next already-added floor or,
    /// if this was the last floor, proceeds to the whole-house merge.
    func finishFloor() {
        if currentFloorIndex + 1 < floors.count {
            currentFloorIndex += 1
            phase = .betweenRooms
        } else {
            Task { await merge() }
        }
    }

    func finishWholeHouse() {
        Task { await merge() }
    }

    // MARK: - Merge (§4.1: StructureBuilder per floor, run inside Task.detached)

    private func merge() async {
        phase = .merging
        guard #available(iOS 17.0, *) else {
            phase = .error("Full Works requires iOS 17 or later.")
            return
        }

        let floorsSnapshot = floors
        do {
            var results: [String: CapturedStructure] = [:]
            for floor in floorsSnapshot {
                guard !floor.rooms.isEmpty else { continue }
                let rooms = floor.rooms.map { $0.room }
                let structure = try await Task.detached(priority: .userInitiated) {
                    try await StructureBuilder(options: []).capturedStructure(from: rooms)
                }.value
                results[floor.id] = structure
            }
            mergedStructures = results
            phase = .complete
        } catch {
            phase = .error("Couldn't merge the scanned rooms: \(error.localizedDescription)")
        }
    }

    // MARK: - Stats (§4.2 completion stat card)

    var scanDurationDescription: String? {
        guard let scanStartedAt else { return nil }
        let seconds = Date().timeIntervalSince(scanStartedAt)
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "under a minute" }
        return "\(minutes) minute\(minutes == 1 ? "" : "s")"
    }

    func reset() {
        propertyName = ""
        floors = []
        currentFloorIndex = 0
        mergedStructuresStorage = [:]
        scanStartedAt = nil
        phase = .setup
    }
}
