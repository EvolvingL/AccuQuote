import SwiftUI

// MARK: - EntitlementManager
//
// Single source of truth for the user's subscription tier.
// Flow:
//   1. On sign-in: reads cached tier from Keychain immediately (no flash)
//   2. Then fetches from server and updates + re-caches
//   3. Server re-validates on every quote generation call — client bypass = silent rejection
//
// Tiers: free | solo | team | crew

@MainActor
final class EntitlementManager: ObservableObject {

    static let shared = EntitlementManager()

    // MARK: - Published

    @Published private(set) var tier: SubscriptionTier = .free
    @Published private(set) var isLoading: Bool = false

    var isPaid: Bool { tier != .free }

    // MARK: - Tier definition

    enum SubscriptionTier: String, Equatable {
        case free
        case solo
        case team
        case crew

        var displayName: String {
            switch self {
            case .free: return "Free"
            case .solo: return "Solo"
            case .team: return "Team"
            case .crew: return "Crew"
            }
        }

        var monthlyPrice: String {
            switch self {
            case .free: return "Free"
            case .solo: return "£99/month"
            case .team: return "£199/month"
            case .crew: return "£349/month"
            }
        }

        var annualPrice: String {
            switch self {
            case .free: return "Free"
            case .solo: return "£990/year"
            case .team: return "£1,990/year"
            case .crew: return "£3,490/year"
            }
        }

        var tagline: String {
            switch self {
            case .free: return "Room scanning only"
            case .solo: return "One person, unlimited quotes"
            case .team: return "2–5 users"
            case .crew: return "6+ users, multi-branch"
            }
        }
    }

    // MARK: - Keychain cache

    private let cacheKey      = "aq_entitlement_tier"
    private let cacheAgeKey   = "aq_entitlement_cached_at"
    // 3 hours: long enough to keep a paying user working through brief offline
    // spells, short enough that a cancelled/downgraded subscription stops granting
    // access within hours rather than a full day. The app also force-refreshes on
    // foreground, so this only bounds the offline grace period.
    private let cacheTTL: TimeInterval = 3 * 3600

    // MARK: - Init

    private init() {
        // Fix #21: honour TTL — if cached tier is older than 24h, default to free
        // and force a server refresh. Prevents cancelled subscriptions persisting indefinitely.
        if let cached    = SecureTokenStore.read(key: cacheKey),
           let t          = SubscriptionTier(rawValue: cached),
           let ageStr     = SecureTokenStore.read(key: cacheAgeKey),
           let ageSeconds = Double(ageStr),
           Date().timeIntervalSince1970 - ageSeconds < cacheTTL {
            tier = t
        }
        // expired or missing cache → tier stays .free, refresh() will hydrate it
    }

    // MARK: - Fetch from server

    func refresh() async {
        guard AuthManager.shared.isSignedIn else {
            tier = .free
            return
        }
        isLoading = true
        defer { isLoading = false }

        guard let token = await AuthManager.shared.currentIdToken(),
              let url = URL(string: "\(AQBackend.baseURL)/api/entitlement") else { return }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tierStr = json["tier"] as? String,
               let fetched = SubscriptionTier(rawValue: tierStr) {
                tier = fetched
                SecureTokenStore.write(key: cacheKey, value: fetched.rawValue)
                // Fix #21: record cache time so TTL check in init() can expire stale entries
                SecureTokenStore.write(key: cacheAgeKey, value: String(Date().timeIntervalSince1970))
            }
        } catch {
            // Network failure — keep cached value
        }
    }

    func clear() {
        tier = .free
        SecureTokenStore.delete(key: cacheKey)
        SecureTokenStore.delete(key: cacheAgeKey)
    }
}
