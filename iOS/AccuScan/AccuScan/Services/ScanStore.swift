import Foundation

// MARK: - ScanStore
// Persists ScanMetadata to UserDefaults. Thumbnail PNG data is stored
// separately on disk (Documents/accuscan_thumbs/) rather than inline in
// the UserDefaults blob, keeping each encode/decode cycle small regardless
// of scan count or thumbnail size.

@MainActor
final class ScanStore: ObservableObject {
    static let shared = ScanStore()

    @Published private(set) var scans: [ScanMetadata] = []

    // v2 key: strips thumbnails from the UserDefaults blob
    private let metaKey   = "accuscan.scan.metadata.v2"
    private let thumbsDir: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir  = docs.appendingPathComponent("accuscan_thumbs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() { load() }

    // MARK: - CRUD

    func save(_ meta: ScanMetadata) {
        // Write thumbnail to disk separately so UserDefaults stays small
        if let data = meta.thumbnailData {
            let url = thumbsDir.appendingPathComponent("\(meta.id.uuidString).png")
            try? data.write(to: url, options: .atomic)
        }
        var stripped = meta
        stripped.thumbnailData = nil
        scans.removeAll { $0.id == stripped.id }
        scans.insert(stripped, at: 0)
        persist()
    }

    func delete(_ id: UUID) {
        scans.removeAll { $0.id == id }
        try? FileManager.default.removeItem(
            at: thumbsDir.appendingPathComponent("\(id.uuidString).png")
        )
        persist()
    }

    func update(_ meta: ScanMetadata) { save(meta) }

    // Lazy disk read — only called when the card is about to render
    func thumbnail(for id: UUID) -> Data? {
        try? Data(contentsOf: thumbsDir.appendingPathComponent("\(id.uuidString).png"))
    }

    // MARK: - Persistence

    private func load() {
        guard let data    = UserDefaults.standard.data(forKey: metaKey),
              let decoded = try? JSONDecoder().decode([ScanMetadata].self, from: data)
        else { return }
        scans = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(scans) else { return }
        UserDefaults.standard.set(data, forKey: metaKey)
    }
}
