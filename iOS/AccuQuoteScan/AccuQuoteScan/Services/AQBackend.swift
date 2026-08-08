import Foundation

// MARK: - Backend configuration
// Single source of truth for the Render server URL.
// No API keys live here — all secrets stay on the server.

enum AQBackend {
    // accuquote.uk is the custom domain — confirmed live and correctly routed
    // to the Render service. The raw accuquote.onrender.com URL previously
    // used here stopped resolving to the same service (404s on every route,
    // including /api/health) and caused every quote-generation attempt to
    // fail with a generic "Server error (404)" — see App Store readiness
    // audit notes, 2 Aug 2026.
    static let baseURL = "https://accuquote.uk"
}
