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
    @Published var elapsedSeconds: Int = 0

    nonisolated static let bgTaskID    = "com.accuquote.scan.asset-download"
    nonisolated private static let readyKey = "aq_photogrammetry_asset_ready"
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
        elapsedSeconds = 0

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
        elapsedSeconds += Int(Self.pollInterval)

        if PhotogrammetrySession.isSupported {
            pollTimer?.invalidate(); pollTimer = nil
            triggerTask?.cancel();   triggerTask = nil
            markReady()
        }
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
        elapsedSeconds = 0
        beginDownloadTrigger()
    }

    func resetReadyFlag() {
        UserDefaults.standard.removeObject(forKey: Self.readyKey)
        assetState = .unknown
    }
}
