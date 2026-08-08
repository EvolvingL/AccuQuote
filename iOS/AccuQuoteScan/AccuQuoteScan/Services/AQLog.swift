import Foundation
import os

// MARK: - AQLog
//
// Thin wrapper around Apple's unified logging (os.Logger) — visible live in
// Console.app/Xcode's console, respects OS-level privacy redaction for
// interpolated values by default (important: auth tokens, emails, job
// descriptions must never end up in a device log a support ticket or crash
// report could surface). No third-party dependency, no network transmission —
// this is a local diagnostic tool, not analytics (see FunnelAnalytics for the
// separate, deliberately-anonymised event pipeline).
//
// One Logger per subsystem area so Console.app's category filter is useful —
// e.g. filter to just "network" while debugging a quote-generation issue
// instead of wading through auth/scanning noise.
//
// Usage:
//   AQLog.network.error("quote/discover failed: \(error, privacy: .public)")
//   AQLog.auth.info("sign-in succeeded")
// Interpolated values default to REDACTED in Console.app for anyone other
// than the developer running it from Xcode — pass `privacy: .public` only for
// values that are genuinely safe to appear in a shared log (status codes,
// error types), never for tokens/emails/free-text user input.

enum AQLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.accuquote1.scan"

    static let network = Logger(subsystem: subsystem, category: "network")
    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let quote = Logger(subsystem: subsystem, category: "quote")
    static let scan = Logger(subsystem: subsystem, category: "scan")
    static let entitlement = Logger(subsystem: subsystem, category: "entitlement")
    static let referral = Logger(subsystem: subsystem, category: "referral")
    static let general = Logger(subsystem: subsystem, category: "general")
}
