import Foundation

// MARK: - ReferralService
//
// Client for the two /api/referral/* endpoints. Registration (register(code:))
// is called once, right after a brand-new account is created — best-effort by
// design: a broken or already-used code must never block someone from
// finishing sign-up, so callers log failures via AQLog and otherwise ignore
// them (see AuthManager.registerPendingReferralIfNeeded).
//
// Info (info()) backs the Profile → Refer screen — the user's own permanent
// code plus how many friends have converted so far.

struct ReferralInfo {
    let code: String
    let referralCount: Int
}

enum ReferralServiceError: Error {
    case notSignedIn
    case invalidCode
    case alreadyRegistered
    case selfReferral
    case other
}

@MainActor
enum ReferralService {

    static func fetchInfo() async throws -> ReferralInfo {
        guard let idToken = await AuthManager.shared.currentIdToken(),
              let url = URL(string: "\(AQBackend.baseURL)/api/referral/me") else {
            throw ReferralServiceError.notSignedIn
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = json["code"] as? String else {
            AQLog.referral.error("fetchInfo: unexpected response")
            throw ReferralServiceError.other
        }
        let count = json["referralCount"] as? Int ?? 0
        return ReferralInfo(code: code, referralCount: count)
    }

    /// Registers a referral code for the CURRENT (just-created) account.
    /// Only ever call this once, immediately after a fresh sign-up — see
    /// AuthManager.registerPendingReferralIfNeeded, the single call site.
    @discardableResult
    static func register(code: String) async -> Bool {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idToken = await AuthManager.shared.currentIdToken(),
              let url = URL(string: "\(AQBackend.baseURL)/api/referral/register") else {
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["code": trimmed])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            if (200...299).contains(http.statusCode) { return true }
            let serverError = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            AQLog.referral.warning("register: server rejected code (\(http.statusCode, privacy: .public)): \(serverError ?? "unknown", privacy: .public)")
            return false
        } catch {
            AQLog.referral.error("register: network failure: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
