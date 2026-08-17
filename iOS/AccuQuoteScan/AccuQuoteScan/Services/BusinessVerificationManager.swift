import SwiftUI

// MARK: - BusinessVerificationManager
//
// Single source of truth for whether the signed-in account's trading name has
// been verified against Companies House. Every account must pass this gate
// before reaching the main app — see AuthGateView — so AccuQuote stays a
// platform for genuine registered UK trades businesses rather than
// unverified individuals.
//
// Flow:
//   1. On sign-in: reads cached verified flag from Keychain immediately (no flash)
//   2. Then fetches the real status from the server and updates + re-caches
//   3. Server is the source of truth — client cache is only to avoid a flash of
//      the gate screen for already-verified users on cold launch

@MainActor
final class BusinessVerificationManager: ObservableObject {

    static let shared = BusinessVerificationManager()

    @Published private(set) var isVerified: Bool = false
    @Published private(set) var businessName: String? = nil
    @Published private(set) var isLoading: Bool = false
    @Published var lastError: String? = nil
    /// Non-matching Companies House results returned after a failed lookup,
    /// shown so the user can see what near-matches exist (e.g. a typo).
    @Published private(set) var candidates: [(name: String, number: String, status: String)] = []
    /// Live search-as-you-type results (see search(query:)) — kept separate
    /// from `candidates` (which only populates after a failed verify attempt)
    /// so the sign-up screen can show a dropdown while the user is still typing.
    @Published private(set) var searchResults: [(name: String, number: String, status: String)] = []
    @Published private(set) var isSearching: Bool = false

    private var searchTask: Task<Void, Never>?

    private let cacheKey = "aq_business_verified"

    private init() {
        if SecureTokenStore.read(key: cacheKey) == "1" {
            isVerified = true
        }
    }

    func refreshStatus() async {
        guard AuthManager.shared.isSignedIn else { isVerified = false; return }
        guard let token = await AuthManager.shared.currentIdToken(),
              let url = URL(string: "\(AQBackend.baseURL)/api/business/verification-status") else { return }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let verified = json["verified"] as? Bool ?? false
                isVerified = verified
                businessName = json["name"] as? String
                SecureTokenStore.write(key: cacheKey, value: verified ? "1" : "0")
            }
        } catch {
            // Network failure — keep cached value
        }
    }

    /// Live search-as-you-type against Companies House, debounced so it
    /// doesn't fire on every keystroke. Populates `searchResults` for a
    /// dropdown — this is the primary way users are meant to pick their
    /// business now, so a missing "Ltd"/"Limited" suffix never surfaces as a
    /// failure: they just tap the correct result from the list.
    func search(query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            searchResults = []
            isSearching = false
            return
        }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)   // 300ms debounce
            guard !Task.isCancelled else { return }

            isSearching = true
            defer { isSearching = false }

            guard let token = await AuthManager.shared.currentIdToken(),
                  var components = URLComponents(string: "\(AQBackend.baseURL)/api/business/search") else { return }
            components.queryItems = [URLQueryItem(name: "q", value: trimmed)]
            guard let url = components.url else { return }

            var req = URLRequest(url: url)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.timeoutInterval = 10

            do {
                let (data, _) = try await URLSession.shared.data(for: req)
                guard !Task.isCancelled else { return }
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let rawResults = json["results"] as? [[String: Any]] {
                    searchResults = rawResults.compactMap { r in
                        guard let n = r["name"] as? String, let num = r["number"] as? String else { return nil }
                        return (name: n, number: num, status: r["status"] as? String ?? "")
                    }
                }
            } catch {
                // Network failure — leave previous results in place rather than clearing
            }
        }
    }

    func clearSearch() {
        searchTask?.cancel()
        searchResults = []
        isSearching = false
    }

    /// Verifies a company selected directly from search(query:)'s dropdown by
    /// its Companies House number — unambiguous, no name-matching involved.
    @discardableResult
    func verify(companyNumber: String) async -> Bool {
        await performVerify(body: ["companyNumber": companyNumber])
    }

    /// Submits a trading name for Companies House verification. Returns true
    /// on success; on failure, `lastError` and `candidates` are populated for
    /// the UI to surface directly rather than a generic failure state. Kept as
    /// a fallback for anyone who types a full name and hits "go" without
    /// using the search dropdown above.
    @discardableResult
    func verify(businessName name: String) async -> Bool {
        await performVerify(body: ["businessName": name])
    }

    private func performVerify(body: [String: String]) async -> Bool {
        isLoading = true
        lastError = nil
        candidates = []
        defer { isLoading = false }

        guard let token = await AuthManager.shared.currentIdToken(),
              let url = URL(string: "\(AQBackend.baseURL)/api/business/verify") else {
            lastError = "Could not reach the verification service. Check your connection and try again."
            return false
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                lastError = "Something went wrong. Please try again."
                return false
            }

            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                lastError = json["error"] as? String ?? "Verification failed. Please try again."
                return false
            }

            let verified = json["verified"] as? Bool ?? false
            if verified {
                isVerified = true
                businessName = json["name"] as? String
                SecureTokenStore.write(key: cacheKey, value: "1")
                return true
            } else {
                if let rawCandidates = json["candidates"] as? [[String: Any]] {
                    candidates = rawCandidates.compactMap { c in
                        guard let n = c["name"] as? String, let num = c["number"] as? String else { return nil }
                        return (name: n, number: num, status: c["status"] as? String ?? "")
                    }
                }
                lastError = "We couldn't find an active company or LLP matching that name on Companies House. Check the spelling matches your official registration."
                return false
            }
        } catch {
            lastError = "Could not reach the verification service. Check your connection and try again."
            return false
        }
    }

    func clear() {
        isVerified = false
        businessName = nil
        candidates = []
        SecureTokenStore.delete(key: cacheKey)
    }

    /// Clears just the error/candidates surfaced from a previous failed
    /// verify() attempt, e.g. when the user edits the name field to retry —
    /// unlike clear(), this never touches isVerified.
    func clearErrorOnly() {
        lastError = nil
        candidates = []
    }
}
