import Foundation

// MARK: - ScanHandoffPayload
//
// AccuScan→AccuQuote Funnel build spec §4.1. Mirrors AccuScan's
// Services/HandoffWriter.swift struct field-for-field so the JSON round-trips
// with no translation layer.

private struct ScanHandoffPayload: Codable {
    let handoffID: String
    let capturedAt: Date
    let length: Double
    let width: Double
    let height: Double
    let floorArea: Double
    let wallCount: Int
    let doorCount: Int
    let windowCount: Int
    let roomType: String
    let scanMethod: String
    var meshURL: String?
}

// MARK: - HandoffImporter
//
// §4.3. Reads the shared App Group container AccuScan wrote to, dedupes by
// handoffID (so a re-launch or repeated onOpenURL doesn't reimport the same
// scan), and constructs a RoomDimensions the existing paywall-gated
// ResultView/LockedResultView flow can render with zero new UI — sets
// coordinator.state = .complete(dims) directly, exactly like a scan
// performed in-app.
//
// Two entry points funnel through the same importIfPending(into:) so there's
// one source of truth for dedupe:
//   - Cold launch / already-running app with a pending unconsumed handoff —
//     call from ContentView's .task, after auth (coordinator only exists then).
//   - Live accuquote://import?handoffID= deep link while the app is running —
//     AccuQuoteScanApp's onOpenURL calls the same method.

@MainActor
enum HandoffImporter {
    static let appGroupID = HandoffWriterConstants.appGroupID
    private static let consumedHandoffIDsKey = "aq_consumed_handoff_ids"

    private static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    /// Checks the shared container for a pending, not-yet-consumed handoff and
    /// imports it into the given coordinator if found. Safe to call on every
    /// ContentView appearance and on every accuquote://import open — a no-op
    /// once the handoff has already been consumed.
    @discardableResult
    static func importIfPending(into coordinator: ScanCoordinator) -> Bool {
        guard let container = containerURL else { return false }
        let fileURL = container.appendingPathComponent("handoff", isDirectory: true)
            .appendingPathComponent("latest_scan.json")
        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(ScanHandoffPayload.self, from: data)
        else { return false }

        guard !isConsumed(payload.handoffID) else { return false }

        let dims = RoomDimensions(
            length: payload.length,
            width: payload.width,
            height: payload.height,
            floorArea: payload.floorArea,
            wallCount: payload.wallCount,
            doorCount: payload.doorCount,
            windowCount: payload.windowCount,
            roomType: payload.roomType,
            scanMethod: mapScanMethod(payload.scanMethod)
        )

        coordinator.state = .complete(dims)
        markConsumed(payload.handoffID)

        // §3: conversion detected — AccuScan should cancel remaining
        // notifications and set convertedToAccuQuote. There's no live
        // process shared between the two apps to call that directly; the
        // shared App Group container is the only channel available, so we
        // write a flag file AccuScan can check on its own next launch.
        writeConversionFlag(handoffID: payload.handoffID)

        FunnelAnalytics.log(.handoffImported(handoffID: payload.handoffID))
        return true
    }

    /// Handles a live accuquote://import?handoffID= open while the app is running.
    /// The handoffID query param isn't required for the import itself (the
    /// container only ever holds the latest handoff), but is validated against
    /// the container's current payload so a stale/mismatched link doesn't
    /// silently import the wrong scan.
    static func handleDeepLink(url: URL, into coordinator: ScanCoordinator) {
        guard url.scheme == "accuquote", url.host == "import" else { return }
        importIfPending(into: coordinator)
    }

    // MARK: - Dedupe

    private static func isConsumed(_ handoffID: String) -> Bool {
        consumedIDs().contains(handoffID)
    }

    private static func markConsumed(_ handoffID: String) {
        var ids = consumedIDs()
        ids.insert(handoffID)
        // Cap growth — only the most recent 50 need remembering in practice
        // since the container only ever holds one pending handoff at a time.
        if ids.count > 50 { ids = Set(ids.suffix(50)) }
        UserDefaults.standard.set(Array(ids), forKey: consumedHandoffIDsKey)
    }

    private static func consumedIDs() -> Set<String> {
        Set(UserDefaults.standard.array(forKey: consumedHandoffIDsKey) as? [String] ?? [])
    }

    // MARK: - Conversion signal back to AccuScan

    private static func writeConversionFlag(handoffID: String) {
        guard let container = containerURL else { return }
        let flagURL = container.appendingPathComponent("handoff", isDirectory: true)
            .appendingPathComponent("did_convert.json")
        let flag = ["handoffID": handoffID, "convertedAt": ISO8601DateFormatter().string(from: Date())]
        if let data = try? JSONEncoder().encode(flag) {
            try? data.write(to: flagURL, options: .atomic)
        }
    }

    // MARK: - ScanMethod mapping
    // AccuScan's ScanMethod and AccuQuote's ScanMethod are separately-declared
    // enums with identical case names (lidar/poseFusion/manual) — mapped by
    // rawValue string rather than assuming binary layout compatibility.

    private static func mapScanMethod(_ raw: String) -> ScanMethod {
        switch raw {
        case "LiDAR":  return .lidar
        case "Camera": return .poseFusion
        default:       return .manual
        }
    }
}

enum HandoffWriterConstants {
    static let appGroupID = "group.com.slickdigital.accu"
}
