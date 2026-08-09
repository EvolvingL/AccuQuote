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
// quote's numbers. It also never deletes a folder still referenced by a
// saved quote's scanArtifactURL/thumbnail (see removeArtifactsOlderThan's
// referencedFolderIDs param) — QuoteHistoryStore caps at 200 quotes by
// count, not by age, so a quote's 3D preview can legitimately outlive the
// 90-day age cutoff and must survive both the manual button (ProfileMenuSheet)
// and the automatic pass (autoCleanupIfDue, called on launch/foreground).

enum ScanStorageManager {

    // MARK: - Scan-in-progress guard
    //
    // Set true by whichever coordinator (ScanCoordinator/SpaceCaptureCoordinator/
    // FullWorksSession) is actively capturing, false again the moment that
    // capture ends (success, error, or reset) — see each coordinator's
    // start/terminal-state call sites. autoCleanupIfDue() checks this before
    // touching aq_scans/ so an automatic cleanup pass can never race a live
    // capture that's mid-write into a scan folder. The manual "Remove 3D
    // models" button in Profile doesn't check this — a user tapping it
    // in-app is never doing so mid-scan (the button isn't reachable from a
    // scanning screen), so the guard only needs to protect the automatic path.
    @MainActor static var isScanInProgress = false

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

    /// Deletes every per-scan folder under aq_scans/ whose modification date
    /// is older than retentionDays AND whose folder name isn't in
    /// `referencedFolderIDs`. The reference check exists because a saved
    /// quote's SavedQuote.scanArtifactURL points straight into
    /// aq_scans/<folder>/ — QuoteHistoryStore caps at 200 quotes by count,
    /// not by age, so a quote saved well over 90 days ago can still be live
    /// in history with its 3D preview/thumbnail depending on a folder that
    /// pure age-based cleanup would otherwise delete out from under it.
    /// Passing the referenced set in (rather than this function reaching
    /// into QuoteHistoryStore itself) keeps this pure/fixture-testable and
    /// is required anyway since QuoteHistoryStore is @MainActor-isolated
    /// while cleanup runs off the main thread — see autoCleanupIfDue().
    ///
    /// referencedFolderIDs defaults to empty so the existing manual "Remove
    /// 3D models" button (ProfileMenuSheet) keeps its current behaviour
    /// unchanged unless a caller opts in.
    ///
    /// Returns the number of folders removed and bytes freed, for the
    /// confirming UI to report back.
    @discardableResult
    static func removeArtifactsOlderThan(
        days retentionDays: Int = defaultRetentionDays,
        now: Date = Date(),
        referencedFolderIDs: Set<String> = []
    ) -> (removedCount: Int, bytesFreed: Int64) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: rootFolder, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return (0, 0)
        }

        var removedCount = 0
        var bytesFreed: Int64 = 0
        for folder in contents {
            guard !referencedFolderIDs.contains(folder.lastPathComponent) else { continue }
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

    // MARK: - Automatic cleanup (launch / foreground)

    private static let lastAutoCleanupKey = "aq_last_auto_cleanup"
    private static let autoCleanupMinInterval: TimeInterval = 24 * 60 * 60   // once/day

    /// Called on cold launch and every foreground — see AccuQuoteScanApp.swift.
    /// Runs the same removeArtifactsOlderThan(90 days) as the manual Profile
    /// button, but: (1) throttled to at most once/day via UserDefaults, so it
    /// never does real I/O work on every single foreground; (2) skipped
    /// entirely while a scan is actively capturing (ScanStorageManager
    /// .isScanInProgress), so it can never race a coordinator that's mid-write
    /// into aq_scans/ — the next foreground/launch will simply retry; (3)
    /// passed the live set of folder IDs still referenced by saved quote
    /// history, computed here on the MainActor (QuoteHistoryStore is
    /// MainActor-isolated) before handing off to a background Task, so the
    /// filesystem work itself never blocks app launch.
    @MainActor
    static func autoCleanupIfDue() {
        guard !isScanInProgress else { return }

        let now = Date()
        if let last = UserDefaults.standard.object(forKey: lastAutoCleanupKey) as? Date,
           now.timeIntervalSince(last) < autoCleanupMinInterval {
            return
        }
        UserDefaults.standard.set(now, forKey: lastAutoCleanupKey)

        let referencedFolderIDs = Set(
            QuoteHistoryStore.shared.quotes.compactMap { quote -> String? in
                guard let urlString = quote.scanArtifactURL, let url = URL(string: urlString) else { return nil }
                // aq_scans/<folderID>/<file> — the folder is the artifact's
                // parent directory name, same layout HistoryThumbnailView's
                // sibling thumb.jpg lookup already assumes.
                return url.deletingLastPathComponent().lastPathComponent
            }
        )

        Task.detached(priority: .utility) {
            let result = removeArtifactsOlderThan(referencedFolderIDs: referencedFolderIDs)
            if result.removedCount > 0 {
                AQLog.general.info("autoCleanupIfDue: removed \(result.removedCount, privacy: .public) folder(s), freed \(formattedSize(result.bytesFreed), privacy: .public)")
            }
        }
    }
}
