import Foundation

// MARK: - Stripe Service
// Calls the AccuQuote server to create a Stripe Payment Link.
// The Stripe secret key never leaves the server.

struct DepositPaymentLink {
    let url: URL
    let depositAmount: Double   // what the customer pays
    let serviceFee: Double      // 1% AccuQuote fee
}

enum StripeServiceError: LocalizedError {
    case invalidURL
    case serverError(String)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .invalidURL:         return "Invalid server URL."
        case .serverError(let m): return m
        case .decodingError:      return "Unexpected response from server."
        }
    }
}

struct StripeService {

    // Point at your Render server — no trailing slash
    private static let baseURL = "https://accuquote.onrender.com"

    static func createPaymentLink(
        depositAmount: Double,
        customerName: String,
        jobDescription: String,
        traderName: String
    ) async throws -> DepositPaymentLink {

        guard let url = URL(string: "\(baseURL)/api/stripe/payment-link") else {
            throw StripeServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "depositAmount":   depositAmount,
            "customerName":    customerName,
            "jobDescription":  jobDescription,
            "traderName":      traderName,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw StripeServiceError.serverError("No HTTP response")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StripeServiceError.decodingError
        }

        if http.statusCode != 200 {
            let msg = json["error"] as? String ?? "Server error (\(http.statusCode))"
            throw StripeServiceError.serverError(msg)
        }

        guard
            let urlString = json["url"] as? String,
            let linkURL   = URL(string: urlString),
            let deposit   = json["depositAmount"] as? Double,
            let fee       = json["serviceFee"] as? Double
        else {
            throw StripeServiceError.decodingError
        }

        return DepositPaymentLink(url: linkURL, depositAmount: deposit, serviceFee: fee)
    }
}
