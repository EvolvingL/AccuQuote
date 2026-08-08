import Foundation

// MARK: - ScanStorageManager (Tri-Mode Scanning build spec §7)
//
// Manages Documents/aq_scans/ — the folder every scan mode's mesh/USDZ/
// thumbnail/CSV/PDF artifacts live under (SpaceMeshExport.scanFolder,
// FloorPlan2DExport.persistToScanFolder, FullWorksOutput.generate, and the
// Room-mode USDZ export in QuoteView.swift's startGeneration all write here).
//
// "Remove 3D models older than 90 days" deletes only the artifact FILES —
// dimensions themselves live in SavedQuote/QuoteHistoryStore, a completely
// separate JSON store this never touches, so cleanup can never lose a
// quote's numbers, only its 3D preview/export files.

enum ScanStorageManager {

    static var rootFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("aq_scans", isDirectory: true)
    }

    static let defaultRetentionDays = 90

    // MARK: - Size

    struct StorageInfo {
        let totalBytes: Int64
        let folderCount: Int
    }

    static func currentStorageInfo() -> StorageInfo {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: rootFolder, includingPropertiesForKeys: nil) else {
            return StorageInfo(totalBytes: 0, folderCount: 0)
        }
        let total = contents.reduce(Int64(0)) { $0 + directorySize($1) }
        return StorageInfo(totalBytes: total, folderCount: contents.count)
    }

    static func directorySize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            total += Int64((try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return total
    }

    /// "128 MB", "1.2 GB" etc — ByteCountFormatter is the standard iOS
    /// convention for this (same formatter class Settings.app itself uses
    /// for storage figures), not a hand-rolled KB/MB/GB switch.
    static func formattedSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - Cleanup (§7 "Remove 3D models older than 90 days")

    /// Pure predicate — fixture-testable without touching the real
    /// filesystem. A folder qualifies for cleanup when its modification
    /// date is more than `retentionDays` before `now`.
    static func isEligibleForCleanup(modificationDate: Date, now: Date, retentionDays: Int) -> Bool {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: now) else { return false }
        return modificationDate < cutoff
    }

    /// Deletes every per-scan folder under aq_scans/ whose modification
    /// date is older than retentionDays. Returns the number of folders
    /// removed and bytes freed, for the confirming UI to report back.
    @discardableResult
    static func removeArtifactsOlderThan(days retentionDays: Int = defaultRetentionDays, now: Date = Date()) -> (removedCount: Int, bytesFreed: Int64) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: rootFolder, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return (0, 0)
        }

        var removedCount = 0
        var bytesFreed: Int64 = 0
        for folder in contents {
            guard let modDate = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  isEligibleForCleanup(modificationDate: modDate, now: now, retentionDays: retentionDays) else { continue }
            let size = directorySize(folder)
            if (try? fm.removeItem(at: folder)) != nil {
                removedCount += 1
                bytesFreed += size
            }
        }
        return (removedCount, bytesFreed)
    }
}
