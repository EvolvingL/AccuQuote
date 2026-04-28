import Foundation
import RealityKit
import BackgroundTasks

// MARK: - Asset state

enum PhotogrammetryAssetState: Equatable {
    case unknown       // Not yet checked
    case downloading   // Triggered download, polling for completion
    case ready         // Asset confirmed present, PhotogrammetrySession can start
    case unsupported   // Device/OS can't support photogrammetry at all (< iOS 17)
}

// MARK: - Manager

/// Manages the one-time OTA download of the ML model that PhotogrammetrySession needs.
///
/// On first launch it triggers the download and polls while the app is foreground.
/// When the app is backgrounded/closed, a BGProcessingTask is scheduled so iOS
/// can continue nudging the download while the device is on Wi-Fi and charging.
@MainActor
final class PhotogrammetryAssetManager: ObservableObject {

    static let shared = PhotogrammetryAssetManager()

    @Published var assetState: PhotogrammetryAssetState = .unknown
    /// 0.0 – 1.0 download progress, derived from MobileAsset cache directory size.
    @Published var downloadProgress: Double = 0.0

    nonisolated static let bgTaskID         = "com.accuquote.scan.asset-download"
    nonisolated private static let readyKey = "aq_photogrammetry_asset_ready"
    /// Approximate total size of the RealityKit photogrammetry ML asset in bytes.
    /// Measured empirically; used only to compute a progress fraction.
    private static let assetTotalBytes: Int64 = 185_000_000   // ~185 MB
    private static let pollInterval: TimeInterval = 1

    private var pollTimer:   Timer?
    private var triggerTask: Task<Void, Never>?

    private init() {}

    // MARK: - Registration (call once at app launch, before app becomes active)

    /// Register the BGProcessingTask handler. Must be called before the app
    /// finishes launching — i.e. from App.init() or AppDelegate.
    nonisolated static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: bgTaskID,
            using: nil
        ) { task in
            guard let task = task as? BGProcessingTask else { return }
            Self.handleBackgroundTask(task)
        }
    }

    // MARK: - Public API

    /// Call once at app launch. Idempotent.
    func prepareAsset() {
        guard #available(iOS 17.0, *) else {
            assetState = .unsupported
            return
        }
        if UserDefaults.standard.bool(forKey: Self.readyKey) {
            assetState = .ready
            return
        }
        if PhotogrammetrySession.isSupported {
            markReady()
            return
        }
        beginDownloadTrigger()
    }

    /// Call when the app moves to the background so iOS can continue the download.
    func scheduleBackgroundTaskIfNeeded() {
        guard assetState == .downloading else { return }
        let request = BGProcessingTaskRequest(identifier: Self.bgTaskID)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false   // allow on battery too
        request.earliestBeginDate = Date(timeIntervalSinceNow: 10)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Call when the app returns to the foreground.
    func resumeForegroundPolling() {
        guard #available(iOS 17.0, *) else { return }
        guard assetState == .downloading else { return }
        // Re-check immediately — the BG task may have completed the download
        if PhotogrammetrySession.isSupported {
            markReady()
            return
        }
        startPolling()
    }

    var isReady: Bool { assetState == .ready }

    // MARK: - Background task handler (nonisolated — called by BGTaskScheduler)

    private nonisolated static func handleBackgroundTask(_ task: BGProcessingTask) {
        // Give ourselves up to 30s of background time to nudge the download
        let work = Task.detached(priority: .userInitiated) {
            guard #available(iOS 17.0, *) else { task.setTaskCompleted(success: true); return }

            // Check if it already completed while we were suspended
            if PhotogrammetrySession.isSupported {
                UserDefaults.standard.set(true, forKey: readyKey)
                task.setTaskCompleted(success: true)
                return
            }

            // Re-trigger the session init to keep the asset download alive
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("aq_pg_bg_trigger")
            try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            _ = try? PhotogrammetrySession(input: tmp)
            try? FileManager.default.removeItem(at: tmp)

            // Wait up to 25s polling, then yield back to iOS
            for _ in 0..<25 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if PhotogrammetrySession.isSupported {
                    UserDefaults.standard.set(true, forKey: readyKey)
                    task.setTaskCompleted(success: true)
                    return
                }
            }

            // Not done yet — schedule another background run
            let request = BGProcessingTaskRequest(identifier: bgTaskID)
            request.requiresNetworkConnectivity = true
            request.requiresExternalPower = false
            request.earliestBeginDate = Date(timeIntervalSinceNow: 60)
            try? BGTaskScheduler.shared.submit(request)

            task.setTaskCompleted(success: false)
        }

        task.expirationHandler = {
            work.cancel()
            // Reschedule so iOS tries again later
            let request = BGProcessingTaskRequest(identifier: bgTaskID)
            request.requiresNetworkConnectivity = true
            request.requiresExternalPower = false
            request.earliestBeginDate = Date(timeIntervalSinceNow: 60)
            try? BGTaskScheduler.shared.submit(request)
        }
    }

    // MARK: - Foreground trigger & polling

    @available(iOS 17.0, *)
    private func beginDownloadTrigger() {
        guard assetState != .downloading else { return }
        assetState = .downloading
        downloadProgress = 0.0

        triggerTask = Task.detached(priority: .userInitiated) {
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("aq_pg_trigger")
            try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            _ = try? PhotogrammetrySession(input: tmp)
            try? FileManager.default.removeItem(at: tmp)
        }

        startPolling()
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval,
                                        repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.poll() }
        }
    }

    private func poll() {
        guard #available(iOS 17.0, *) else { return }

        if PhotogrammetrySession.isSupported {
            downloadProgress = 1.0
            pollTimer?.invalidate(); pollTimer = nil
            triggerTask?.cancel();   triggerTask = nil
            markReady()
            return
        }

        // Measure how much of the asset has been written to the MobileAsset cache.
        // iOS stores partial downloads under /var/MobileAsset/AssetsV2/
        // in a directory whose name contains "RealityKit".
        let measured = Self.measureAssetCacheBytes()
        if measured > 0 {
            // Cap at 0.97 so the bar never falsely claims 100% before isSupported fires
            downloadProgress = min(Double(measured) / Double(Self.assetTotalBytes), 0.97)
        } else {
            // Cache dir not found yet — show a slow creep so the bar isn't static
            downloadProgress = min(downloadProgress + 0.002, 0.15)
        }
    }

    /// Returns the total bytes written to any MobileAsset directory that looks
    /// like the RealityKit photogrammetry asset. Returns 0 if not found.
    private static func measureAssetCacheBytes() -> Int64 {
        // Candidate locations — iOS puts MobileAssets in /var/MobileAsset on device.
        // The sandbox exposes this under a path accessible to third-party apps.
        let candidates: [URL] = [
            URL(fileURLWithPath: "/var/MobileAsset/AssetsV2"),
            URL(fileURLWithPath: "/private/var/MobileAsset/AssetsV2"),
        ]
        let fm = FileManager.default
        for base in candidates {
            guard let contents = try? fm.contentsOfDirectory(
                at: base,
                includingPropertiesForKeys: nil
            ) else { continue }
            for dir in contents where dir.lastPathComponent.contains("RealityKit") {
                return directorySize(at: dir)
            }
        }
        return 0
    }

    private static func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            total += Int64((try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return total
    }

    private func markReady() {
        UserDefaults.standard.set(true, forKey: Self.readyKey)
        assetState = .ready
        pollTimer?.invalidate(); pollTimer = nil
        triggerTask?.cancel(); triggerTask = nil
    }

    func retry() {
        guard #available(iOS 17.0, *) else { return }
        triggerTask?.cancel(); triggerTask = nil
        pollTimer?.invalidate(); pollTimer = nil
        downloadProgress = 0.0
        beginDownloadTrigger()
    }

    func resetReadyFlag() {
        UserDefaults.standard.removeObject(forKey: Self.readyKey)
        assetState = .unknown
    }
}
