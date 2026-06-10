import Foundation

// MARK: - Stripe Service
// Calls the AccuQuote server to create a Stripe Payment Link.
// The Stripe secret key never leaves the server.
// Auth token is attached so the server can verify the user is on a paid tier.

struct DepositPaymentLink {
    let url: URL
    let depositAmount: Double   // what the customer pays
    let serviceFee: Double      // 1% AccuQuote fee
}

enum StripeServiceError: LocalizedError {
    case invalidURL
    case notAuthenticated
    case serverError(String)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .invalidURL:         return "Invalid server URL."
        case .notAuthenticated:   return "Please sign in to request a deposit."
        case .serverError(let m): return m
        case .decodingError:      return "Unexpected response from server."
        }
    }
}

struct StripeService {

    static func createPaymentLink(
        depositAmount: Double,
        maxAmount: Double = .greatestFiniteMagnitude,
        customerName: String,
        jobDescription: String,
        traderName: String
    ) async throws -> DepositPaymentLink {

        // H4: validate the amount client-side. A non-finite / negative / zero /
        // over-quote amount must never reach Stripe (JSONSerialization also throws
        // on non-finite Doubles, so guarding here gives a clean user-facing error).
        let rounded = (depositAmount * 100).rounded() / 100   // pence precision
        guard rounded.isFinite, rounded >= 0.50, rounded <= maxAmount else {
            throw StripeServiceError.serverError(
                "Enter a deposit between £0.50 and the quote total.")
        }

        guard let url = URL(string: "\(AQBackend.baseURL)/api/stripe/payment-link") else {
            throw StripeServiceError.invalidURL
        }

        // The server endpoint requires requireAuth + requirePaidTier — attach token
        guard let idToken = await AuthManager.shared.currentIdToken() else {
            throw StripeServiceError.notAuthenticated
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json",   forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)",  forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "depositAmount":   rounded,
            "customerName":    customerName,
            "jobDescription":  jobDescription,
            "traderName":      traderName,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw StripeServiceError.serverError("No HTTP response")
        }

        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]

        if http.statusCode == 401 {
            throw StripeServiceError.notAuthenticated
        }
        if http.statusCode == 403 {
            let msg = json["error"] as? String ?? "subscription_required"
            throw StripeServiceError.serverError(msg == "subscription_required"
                ? "A paid subscription is required to request deposits."
                : msg)
        }
        if http.statusCode != 200 {
            let msg = json["error"] as? String ?? "Server error (\(http.statusCode))"
            throw StripeServiceError.serverError(msg)
        }

        guard
            let urlString = json["url"] as? String,
            let linkURL   = URL(string: urlString)
        else {
            let raw = String(data: data, encoding: .utf8) ?? "unreadable"
            throw StripeServiceError.serverError("Missing payment URL in response: \(raw)")
        }

        let deposit = json["depositAmount"] as? Double ?? 0
        let fee     = json["serviceFee"]    as? Double ?? 0

        return DepositPaymentLink(url: linkURL, depositAmount: deposit, serviceFee: fee)
    }
}
