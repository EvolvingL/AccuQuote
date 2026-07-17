import StoreKit

// MARK: - StoreKitManager
//
// Handles Apple In-App Purchase subscriptions for the Solo/Team/Crew tiers
// (Guideline 3.1.1 — subscriptions that unlock functionality inside the app
// must go through StoreKit, not an external payment page).
//
// Flow:
//   1. loadProducts() fetches the 6 subscription products from App Store Connect.
//   2. purchase(_:) drives the native purchase sheet, then reports the transaction
//      to our server, which independently re-verifies it with Apple and writes
//      the entitlement to Firestore (see /api/iap/verify on the server).
//   3. listenForTransactions() runs for the app's lifetime and catches renewals,
//      refunds, and restores that happen outside an explicit purchase tap.
//
// The deposit-payment-link flow (StripeService.swift) is unaffected — that's a
// real-world service payment between the tradesperson and their own customer,
// which is exempt from the IAP requirement.

@MainActor
final class StoreKitManager: ObservableObject {

    static let shared = StoreKitManager()

    @Published private(set) var products: [Product] = []
    @Published private(set) var purchaseInProgress = false

    // Must exactly match the Product IDs created in App Store Connect and in
    // Products.storekit (the local testing configuration).
    //
    // Prefix is "com.accuquote1.scan" (with the "1") to match the app's actual
    // bundle ID — com.accuquote.scan was unavailable to (re)register, so the
    // app ships as com.accuquote1.scan instead.
    //
    // Team/Crew have no annual product — App Store Connect's GBP price tier
    // picker doesn't offer a tier anywhere near £1,990/£3,490 (confirmed by
    // searching "1990" and only finding £19.90 / £199.00), so those two tiers
    // are monthly-only. Solo annual (£990) is within the available tiers.
    static let productIDs: [String] = [
        "com.accuquote1.scan.solo.monthly",
        "com.accuquote1.scan.solo.annual",
        "com.accuquote1.scan.team.monthly",
        "com.accuquote1.scan.crew.monthly",
    ]

    private var updateListenerTask: Task<Void, Never>?

    private init() {
        updateListenerTask = listenForTransactions()
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - Load products

    func loadProducts() async {
        guard products.isEmpty else { return }
        do {
            products = try await Product.products(for: Self.productIDs)
        } catch {
            print("[StoreKit] Failed to load products: \(error)")
        }
    }

    func product(tier: EntitlementManager.SubscriptionTier, interval: PaywallSheet.PayInterval) -> Product? {
        let suffix = interval == .monthly ? "monthly" : "annual"
        let id = "com.accuquote1.scan.\(tier.rawValue).\(suffix)"
        return products.first(where: { $0.id == id })
    }

    // MARK: - Purchase

    enum PurchaseError: LocalizedError {
        case userCancelled
        case pending
        case verificationFailed
        case unknown

        var errorDescription: String? {
            switch self {
            case .userCancelled:      return nil // user-initiated cancel — don't show an error
            case .pending:            return "Purchase is pending approval (e.g. Ask to Buy)."
            case .verificationFailed: return "Could not verify purchase. Please try again."
            case .unknown:            return "Something went wrong. Please try again."
            }
        }
    }

    func purchase(_ product: Product) async throws {
        purchaseInProgress = true
        defer { purchaseInProgress = false }

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await reportTransactionToServer(transaction)
            await transaction.finish()

        case .userCancelled:
            throw PurchaseError.userCancelled

        case .pending:
            throw PurchaseError.pending

        @unknown default:
            throw PurchaseError.unknown
        }
    }

    // MARK: - Restore

    func restorePurchases() async throws {
        try await AppStore.sync()
        await refreshEntitlementFromServer()
    }

    // MARK: - Transaction verification

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw PurchaseError.verificationFailed
        case .verified(let safe):
            return safe
        }
    }

    // MARK: - Listen for background transaction updates (renewals, refunds, etc.)

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await update in Transaction.updates {
                guard let self else { continue }
                do {
                    let transaction = try await self.checkVerified(update)
                    await self.reportTransactionToServer(transaction)
                    await transaction.finish()
                } catch {
                    print("[StoreKit] Transaction update verification failed: \(error)")
                }
            }
        }
    }

    // MARK: - Tell our server about the purchase
    //
    // We send only IDs, never the client's claim of what tier/price was paid —
    // the server independently re-verifies the transaction with Apple's App
    // Store Server API before writing anything to Firestore.

    private func reportTransactionToServer(_ transaction: Transaction) async {
        guard let idToken = await AuthManager.shared.currentIdToken(),
              let url = URL(string: "\(AQBackend.baseURL)/api/iap/verify") else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "transactionId": String(transaction.id),
        ])

        _ = try? await URLSession.shared.data(for: req)
        await refreshEntitlementFromServer()
    }

    private func refreshEntitlementFromServer() async {
        await EntitlementManager.shared.refresh()
    }
}
