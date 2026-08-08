import Foundation

// MARK: - FunnelEvent (AccuQuote side)
//
// AccuScan→AccuQuote Funnel build spec §5. AccuQuote only emits the two
// events that happen on its own side of the funnel — everything upstream
// (scan_completed, persona_selected, upsell_shown/tapped/dismissed,
// handoff_initiated) is emitted by AccuScan's own FunnelAnalytics
// (Services/FunnelAnalytics.swift there), a structurally identical but
// separately-compiled type since the two apps share no framework target.
//
// Privacy choke-point (§5, §8): this enum's cases carry ONLY anonymised
// funnel parameters (handoffID, tier, a variant bucket) — never persona,
// scan dimensions, or any other behavioural/quote content. Enforced by
// construction: FunnelEvent simply has no case that can carry that data.

enum FunnelEvent {
    case handoffImported(handoffID: String)
    case firstQuoteGenerated
    case subscribed(tier: String)

    var name: String {
        switch self {
        case .handoffImported:     return "handoff_imported"
        case .firstQuoteGenerated: return "accuquote_first_quote"
        case .subscribed:          return "accuquote_subscribed"
        }
    }

    var params: [String: String] {
        switch self {
        case .handoffImported(let handoffID): return ["handoffID": handoffID]
        case .firstQuoteGenerated:             return [:]
        case .subscribed(let tier):            return ["tier": tier]
        }
    }
}

// MARK: - FunnelAnalytics
//
// Batched, best-effort POST to AQBackend. §5's endpoint doesn't exist on the
// server yet (server/index.js has no generic event-ingestion route as of
// this pass) — this queues locally and flushes opportunistically so it's
// ready the moment `/api/events` ships; a failed POST just leaves the queue
// for the next flush rather than dropping events.

@MainActor
final class FunnelAnalytics {
    static let shared = FunnelAnalytics()

    private static let queueKey = "aq_funnel_event_queue"
    private var queue: [[String: Any]] = []

    private init() { load() }

    static func log(_ event: FunnelEvent) {
        shared.enqueue(event)
    }

    private func enqueue(_ event: FunnelEvent) {
        var record: [String: Any] = [
            "event": event.name,
            "loggedAt": ISO8601DateFormatter().string(from: Date()),
        ]
        for (k, v) in event.params { record[k] = v }
        queue.append(record)
        persist()
        Task { await flush() }
    }

    /// Best-effort flush. Placeholder endpoint — see header comment.
    private func flush() async {
        guard !queue.isEmpty,
              let url = URL(string: "\(AQBackend.baseURL)/api/events")
        else { return }
        guard let body = try? JSONSerialization.data(withJSONObject: ["events": queue]) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        if let (_, response) = try? await URLSession.shared.data(for: request),
           let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
            queue.removeAll()
            persist()
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.queueKey),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            queue = decoded
        }
    }

    private func persist() {
        if let data = try? JSONSerialization.data(withJSONObject: queue) {
            UserDefaults.standard.set(data, forKey: Self.queueKey)
        }
    }
}
