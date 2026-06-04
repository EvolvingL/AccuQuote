import Foundation

// MARK: - ScanStore
// Lightweight in-memory + UserDefaults persistence for scan metadata.
// Full CapturedRoom data is not serialisable — we store the metadata
// and the USDZ file path, then re-load the USDZ for export.

@MainActor
final class ScanStore: ObservableObject {
    static let shared = ScanStore()

    @Published private(set) var scans: [ScanMetadata] = []

    private let storageKey = "accuscan.scan.metadata"

    private init() { load() }

    // MARK: - CRUD

    func save(_ meta: ScanMetadata) {
        scans.removeAll { $0.id == meta.id }
        scans.insert(meta, at: 0)    // newest first
        persist()
    }

    func delete(_ id: UUID) {
        scans.removeAll { $0.id == id }
        persist()
    }

    func update(_ meta: ScanMetadata) { save(meta) }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ScanMetadata].self, from: data)
        else { return }
        scans = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(scans) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
