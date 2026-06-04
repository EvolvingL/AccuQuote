import Foundation

// MARK: - Backend configuration
// Single source of truth for the Render server URL.
// No API keys live here — all secrets stay on the server.

enum AQBackend {
    static let baseURL = "https://accuquote.onrender.com"
}
