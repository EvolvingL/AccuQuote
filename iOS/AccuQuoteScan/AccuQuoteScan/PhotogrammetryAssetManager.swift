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
    private static let pollInterval: TimeInterval = 3

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

        // Instantiating PhotogrammetrySession against any directory causes iOS
        // to queue the MobileAsset download automatically.
        triggerTask = Task.detached(priority: .background) {
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("aq_pg_trigger_\(Int(Date().timeIntervalSince1970))")
            try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            // Minimal valid JPEG so the session init doesn't throw immediately
            let jpeg: [UInt8] = [
                0xFF,0xD8,0xFF,0xE0,0x00,0x10,0x4A,0x46,0x49,0x46,0x00,0x01,
                0x01,0x00,0x00,0x01,0x00,0x01,0x00,0x00,0xFF,0xDB,0x00,0x43,
                0x00,0x08,0x06,0x06,0x07,0x06,0x05,0x08,0x07,0x07,0x07,0x09,
                0x09,0x08,0x0A,0x0C,0x14,0x0D,0x0C,0x0B,0x0B,0x0C,0x19,0x12,
                0x13,0x0F,0x14,0x1D,0x1A,0x1F,0x1E,0x1D,0x1A,0x1C,0x1C,0x20,
                0x24,0x2E,0x27,0x20,0x22,0x2C,0x23,0x1C,0x1C,0x28,0x37,0x29,
                0x2C,0x30,0x31,0x34,0x34,0x34,0x1F,0x27,0x39,0x3D,0x38,0x32,
                0x3C,0x2E,0x33,0x34,0x32,0xFF,0xC0,0x00,0x0B,0x08,0x00,0x01,
                0x00,0x01,0x01,0x01,0x11,0x00,0xFF,0xC4,0x00,0x1F,0x00,0x00,
                0x01,0x05,0x01,0x01,0x01,0x01,0x01,0x01,0x00,0x00,0x00,0x00,
                0x00,0x00,0x00,0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x08,
                0x09,0x0A,0x0B,0xFF,0xDA,0x00,0x08,0x01,0x01,0x00,0x00,0x3F,
                0x00,0xFB,0xD4,0xFF,0xD9
            ]
            try? Data(jpeg).write(to: tmp.appendingPathComponent("placeholder.jpg"))
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
