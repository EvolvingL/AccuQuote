import Foundation
import RealityKit
import Combine

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
/// Non-LiDAR devices must wait for this to complete before scanning is available.
/// Once ready it is persisted in UserDefaults — all subsequent launches are instant.
@MainActor
final class PhotogrammetryAssetManager: ObservableObject {

    static let shared = PhotogrammetryAssetManager()

    @Published var assetState: PhotogrammetryAssetState = .unknown
    @Published var elapsedSeconds: Int = 0

    nonisolated private static let readyKey    = "aq_photogrammetry_asset_ready"
    private static let pollInterval: TimeInterval = 1

    private var pollTimer:   Timer?
    private var triggerTask: Task<Void, Never>?

    private init() {}

    // MARK: - Public API

    /// Call once at app launch. Idempotent.
    func prepareAsset() {
        guard #available(iOS 17.0, *) else {
            assetState = .unsupported
            return
        }
        // Already confirmed ready
        if UserDefaults.standard.bool(forKey: Self.readyKey) {
            assetState = .ready
            return
        }
        // Already present on this device right now
        if PhotogrammetrySession.isSupported {
            markReady()
            return
        }
        beginDownloadTrigger()
    }

    var isReady: Bool { assetState == .ready }

    // MARK: - Download trigger

    @available(iOS 17.0, *)
    private func beginDownloadTrigger() {
        guard assetState != .downloading else { return }
        assetState = .downloading
        elapsedSeconds = 0

        // Calling PhotogrammetrySession(input:) — even on an empty/invalid path —
        // is sufficient to cause iOS to queue the MobileAsset download.
        // We use .userInitiated so iOS treats it as a foreground request,
        // not a deferred background task, which gives it higher download priority.
        triggerTask = Task.detached(priority: .userInitiated) {
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("aq_pg_trigger")
            try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            _ = try? PhotogrammetrySession(input: tmp)
            // Re-trigger every 30s while still downloading — keeps the asset
            // request alive if iOS de-prioritises it in the background.
            try? await Task.sleep(nanoseconds: 30_000_000_000)
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
    }

    /// Retry trigger — e.g. user tapped "Try again" after a long wait
    func retry() {
        guard #available(iOS 17.0, *) else { return }
        triggerTask?.cancel(); triggerTask = nil
        pollTimer?.invalidate(); pollTimer = nil
        elapsedSeconds = 0
        beginDownloadTrigger()
    }

    /// Remove persisted flag (for testing/reset purposes)
    func resetReadyFlag() {
        UserDefaults.standard.removeObject(forKey: Self.readyKey)
        assetState = .unknown
    }
}
