import Foundation
import RealityKit
import Combine

// MARK: - Asset state

enum PhotogrammetryAssetState: Equatable {
    case unknown          // Not yet checked
    case downloading      // Triggered download, polling for completion
    case ready            // PhotogrammetrySession.isSupported == true and session can start
    case unavailable      // Device/OS doesn't support it at all (< iOS 17 or non-ARKit)
    case failed(String)   // Download timed out or repeated failures
}

// MARK: - Manager

/// Owns the lifecycle of the OTA ML asset that PhotogrammetrySession needs.
///
/// How it works:
/// 1. On first launch, check if the asset is already present (isSupported).
/// 2. If not, create a short-lived PhotogrammetrySession to trigger the OTA
///    asset download — iOS queues it automatically when any app requests it.
/// 3. Poll every few seconds until isSupported becomes true or we time out.
/// 4. Persist readiness in UserDefaults so subsequent launches skip the check.
@MainActor
final class PhotogrammetryAssetManager: ObservableObject {

    static let shared = PhotogrammetryAssetManager()

    @Published var assetState: PhotogrammetryAssetState = .unknown
    @Published var progressMessage: String = ""

    nonisolated private static let readyKey = "aq_photogrammetry_asset_ready"
    private static let pollInterval: TimeInterval = 4
    private static let timeoutAfter: TimeInterval = 300  // 5 minutes max

    private var pollTimer: Timer?
    private var elapsed:   TimeInterval = 0
    private var triggerTask: Task<Void, Never>?

    private init() {}

    // MARK: - Public API

    /// Call once at app launch. Safe to call multiple times.
    func prepareAsset() {
        // If the device can't ever support photogrammetry, bail immediately
        guard #available(iOS 17.0, *) else {
            assetState = .unavailable
            return
        }

        // Already confirmed ready in a previous session
        if UserDefaults.standard.bool(forKey: Self.readyKey) {
            assetState = .ready
            return
        }

        // Check right now — maybe the asset arrived since last launch
        if PhotogrammetrySession.isSupported {
            markReady()
            return
        }

        // Start the download + polling cycle
        beginDownloadTrigger()
    }

    /// Returns true if photogrammetry is safe to use right now.
    var isReady: Bool { assetState == .ready }

    // MARK: - Download trigger

    @available(iOS 17.0, *)
    private func beginDownloadTrigger() {
        assetState = .downloading
        progressMessage = "Downloading AI scanning model…"
        elapsed = 0

        // Creating a PhotogrammetrySession with any valid temp directory causes
        // iOS to queue the MobileAsset download in the background.
        triggerTask = Task.detached(priority: .background) {
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("aq_pg_trigger_\(Int(Date().timeIntervalSince1970))")
            try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            // Write a placeholder image so the session init doesn't immediately throw
            let placeholder = tmp.appendingPathComponent("placeholder.jpg")
            if !FileManager.default.fileExists(atPath: placeholder.path) {
                // 1×1 white JPEG
                let bytes: [UInt8] = [
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
                    0x09,0x0A,0x0B,0xFF,0xC4,0x00,0xB5,0x10,0x00,0x02,0x01,0x03,
                    0x03,0x02,0x04,0x03,0x05,0x05,0x04,0x04,0x00,0x00,0x01,0x7D,
                    0x01,0x02,0x03,0x00,0x04,0x11,0x05,0x12,0x21,0x31,0x41,0x06,
                    0x13,0x51,0x61,0x07,0x22,0x71,0x14,0x32,0x81,0x91,0xA1,0x08,
                    0x23,0x42,0xB1,0xC1,0x15,0x52,0xD1,0xF0,0x24,0x33,0x62,0x72,
                    0x82,0x09,0x0A,0x16,0x17,0x18,0x19,0x1A,0x25,0x26,0x27,0x28,
                    0x29,0x2A,0x34,0x35,0x36,0x37,0x38,0x39,0x3A,0x43,0x44,0x45,
                    0x46,0x47,0x48,0x49,0x4A,0x53,0x54,0x55,0x56,0x57,0x58,0x59,
                    0x5A,0x63,0x64,0x65,0x66,0x67,0x68,0x69,0x6A,0x73,0x74,0x75,
                    0x76,0x77,0x78,0x79,0x7A,0x83,0x84,0x85,0x86,0x87,0x88,0x89,
                    0x8A,0x93,0x94,0x95,0x96,0x97,0x98,0x99,0x9A,0xA2,0xA3,0xA4,
                    0xA5,0xA6,0xA7,0xA8,0xA9,0xAA,0xB2,0xB3,0xB4,0xB5,0xB6,0xB7,
                    0xB8,0xB9,0xBA,0xC2,0xC3,0xC4,0xC5,0xC6,0xC7,0xC8,0xC9,0xCA,
                    0xD2,0xD3,0xD4,0xD5,0xD6,0xD7,0xD8,0xD9,0xDA,0xE1,0xE2,0xE3,
                    0xE4,0xE5,0xE6,0xE7,0xE8,0xE9,0xEA,0xF1,0xF2,0xF3,0xF4,0xF5,
                    0xF6,0xF7,0xF8,0xF9,0xFA,0xFF,0xDA,0x00,0x08,0x01,0x01,0x00,
                    0x00,0x3F,0x00,0xFB,0xD4,0xFF,0xD9
                ]
                try? Data(bytes).write(to: placeholder)
            }
            _ = try? PhotogrammetrySession(input: tmp)
            try? FileManager.default.removeItem(at: tmp)
        }

        // Poll until ready or timed out
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

        elapsed += Self.pollInterval

        if PhotogrammetrySession.isSupported {
            pollTimer?.invalidate()
            pollTimer = nil
            triggerTask?.cancel()
            triggerTask = nil
            markReady()
            return
        }

        // Update progress message with elapsed time hint
        let minutes = Int(elapsed / 60)
        let seconds = Int(elapsed) % 60
        if elapsed < 30 {
            progressMessage = "Downloading AI scanning model…"
        } else if elapsed < 120 {
            progressMessage = "Still downloading (\(seconds)s) — needs Wi-Fi"
        } else {
            progressMessage = "Downloading (\(minutes)m \(seconds % 60)s) — keep app open"
        }

        if elapsed >= Self.timeoutAfter {
            pollTimer?.invalidate()
            pollTimer = nil
            triggerTask?.cancel()
            triggerTask = nil
            assetState = .failed("Download timed out. Connect to Wi-Fi and try again.")
        }
    }

    private func markReady() {
        UserDefaults.standard.set(true, forKey: Self.readyKey)
        assetState = .ready
        progressMessage = ""
    }

    /// Call when user explicitly requests a retry after failure
    func retry() {
        guard #available(iOS 17.0, *) else { return }
        elapsed = 0
        beginDownloadTrigger()
    }

    /// Reset persisted state (e.g. for testing)
    func resetReadyFlag() {
        UserDefaults.standard.removeObject(forKey: Self.readyKey)
        assetState = .unknown
    }
}
