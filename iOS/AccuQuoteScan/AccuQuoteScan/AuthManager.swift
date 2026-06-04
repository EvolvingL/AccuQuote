import SwiftUI
import AuthenticationServices
import CryptoKit

// MARK: - AuthManager
//
// Handles all authentication for AccuQuote.
// Uses Firebase Auth via the REST API — no Firebase SDK dependency required.
// Session token is stored in Keychain via SecureTokenStore.
//
// Supported methods:
//   • Email + password (sign in / sign up / change password / reset password)
//   • Sign in with Apple  (ASAuthorizationAppleIDProvider)
//   • Sign in with Google (handled via web OAuth flow in SFSafariViewController)
//   • Sign in with Facebook (handled via web OAuth flow)
//
// The Firebase project Web API key is NOT a secret — it is safe to bundle in the app.
// It only identifies the project, not authenticates access.

@MainActor
final class AuthManager: NSObject, ObservableObject {

    static let shared = AuthManager()

    // MARK: - Published state

    @Published private(set) var isSignedIn: Bool = false
    @Published private(set) var userEmail: String = ""
    @Published private(set) var userId: String = ""
    @Published private(set) var isLoading: Bool = true
    @Published var authError: String? = nil

    // MARK: - Firebase REST config
    // Web API key — safe to include in the app (identifies project, not a secret)
    private let firebaseApiKey = "AIzaSyDKafeB_gQUi24DMDsqqvNoOPvFjmcxDVA"
    private var idToken: String? = nil
    private var refreshToken: String? = nil
    private var tokenExpiry: Date = .distantPast

    // MARK: - Keychain keys
    private let keychainIdToken      = "aq_firebase_id_token"
    private let keychainRefreshToken = "aq_firebase_refresh_token"
    private let keychainUserId       = "aq_firebase_user_id"
    private let keychainEmail        = "aq_firebase_email"

    // MARK: - Apple Sign-In nonce
    // nonisolated(unsafe) allows the nonisolated delegate to read this safely
    nonisolated(unsafe) private var currentNonce: String?

    // MARK: - Init

    override private init() {
        super.init()
        Task { await restoreSession() }
    }

    // MARK: - Session restoration

    private func restoreSession() async {
        defer { isLoading = false }
        guard let stored = SecureTokenStore.read(key: keychainRefreshToken),
              !stored.isEmpty else { return }
        refreshToken = stored
        userId = SecureTokenStore.read(key: keychainUserId) ?? ""
        userEmail = SecureTokenStore.read(key: keychainEmail) ?? ""
        // Attempt to get a fresh ID token
        if await refreshIdToken() {
            isSignedIn = true
        } else {
            clearLocalSession()
        }
    }

    // MARK: - Current token (for API requests)

    func currentIdToken() async -> String? {
        if let token = idToken, tokenExpiry > Date().addingTimeInterval(60) {
            return token
        }
        if await refreshIdToken() { return idToken }
        return nil
    }

    // MARK: - Email / Password sign-in

    func signIn(email: String, password: String) async {
        authError = nil
        isLoading = true
        defer { isLoading = false }

        let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=\(firebaseApiKey)")!
        let body = ["email": email, "password": password, "returnSecureToken": true] as [String: Any]

        do {
            let result = try await postFirebase(url: url, body: body)
            await handleTokenResult(result, email: email)
        } catch {
            authError = friendlyError(error)
        }
    }

    // MARK: - Email / Password sign-up

    func signUp(email: String, password: String) async {
        authError = nil
        isLoading = true
        defer { isLoading = false }

        let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=\(firebaseApiKey)")!
        let body = ["email": email, "password": password, "returnSecureToken": true] as [String: Any]

        do {
            let result = try await postFirebase(url: url, body: body)
            await handleTokenResult(result, email: email)
        } catch {
            authError = friendlyError(error)
        }
    }

    // MARK: - Password reset email

    func sendPasswordReset(email: String) async {
        authError = nil
        let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=\(firebaseApiKey)")!
        let body: [String: Any] = ["requestType": "PASSWORD_RESET", "email": email]
        _ = try? await postFirebase(url: url, body: body)
    }

    // MARK: - Sign in with Apple

    func signInWithApple() {
        currentNonce = randomNonceString()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(currentNonce!)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    // MARK: - Sign out

    func signOut() {
        clearLocalSession()
        NotificationCenter.default.post(name: .aqSignOut, object: nil)
    }

    // MARK: - Private helpers

    private func handleTokenResult(_ result: [String: Any], email: String) async {
        guard let token    = result["idToken"]      as? String,
              let refresh  = result["refreshToken"] as? String,
              let uid      = result["localId"]      as? String else {
            authError = "Invalid response from auth server"
            return
        }
        let expiresIn = TimeInterval(result["expiresIn"] as? String ?? "3600") ?? 3600
        idToken      = token
        refreshToken = refresh
        userId       = uid
        userEmail    = email
        tokenExpiry  = Date().addingTimeInterval(expiresIn)

        SecureTokenStore.write(key: keychainIdToken,      value: token)
        SecureTokenStore.write(key: keychainRefreshToken, value: refresh)
        SecureTokenStore.write(key: keychainUserId,       value: uid)
        SecureTokenStore.write(key: keychainEmail,        value: email)

        isSignedIn = true
    }

    @discardableResult
    private func refreshIdToken() async -> Bool {
        guard let refresh = refreshToken, !refresh.isEmpty else { return false }
        let url = URL(string: "https://securetoken.googleapis.com/v1/token?key=\(firebaseApiKey)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = "grant_type=refresh_token&refresh_token=\(refresh)".data(using: .utf8)

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token   = json["id_token"]      as? String,
              let newRefresh = json["refresh_token"] as? String else { return false }

        let expiresIn = TimeInterval(json["expires_in"] as? String ?? "3600") ?? 3600
        idToken      = token
        refreshToken = newRefresh
        tokenExpiry  = Date().addingTimeInterval(expiresIn)
        SecureTokenStore.write(key: keychainIdToken,      value: token)
        SecureTokenStore.write(key: keychainRefreshToken, value: newRefresh)
        return true
    }

    private func postFirebase(url: URL, body: [String: Any]) async throws -> [String: Any] {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthError.invalidResponse
        }
        if let errBlock = json["error"] as? [String: Any],
           let msg = errBlock["message"] as? String {
            throw AuthError.firebaseError(msg)
        }
        return json
    }

    private func clearLocalSession() {
        idToken = nil; refreshToken = nil
        userId = ""; userEmail = ""
        tokenExpiry = .distantPast
        isSignedIn = false
        SecureTokenStore.delete(key: keychainIdToken)
        SecureTokenStore.delete(key: keychainRefreshToken)
        SecureTokenStore.delete(key: keychainUserId)
        SecureTokenStore.delete(key: keychainEmail)
    }

    private func friendlyError(_ error: Error) -> String {
        if let e = error as? AuthError {
            switch e {
            case .firebaseError(let msg):
                switch msg {
                case "EMAIL_NOT_FOUND":          return "No account found with that email."
                case "INVALID_PASSWORD":         return "Incorrect password."
                case "EMAIL_EXISTS":             return "An account already exists with that email."
                case "WEAK_PASSWORD : Password should be at least 6 characters":
                                                 return "Password must be at least 6 characters."
                case "INVALID_EMAIL":            return "Please enter a valid email address."
                case "TOO_MANY_ATTEMPTS_TRY_LATER": return "Too many attempts. Please try again later."
                default:                         return msg
                }
            case .invalidResponse: return "Unexpected response. Please try again."
            }
        }
        return error.localizedDescription
    }

    // MARK: - Apple nonce helpers

    private func randomNonceString(length: Int = 32) -> String {
        var result = ""
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var remaining = length
        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            _ = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            for r in randoms where remaining > 0 {
                if r < chars.count { result.append(chars[Int(r)]); remaining -= 1 }
            }
        }
        return result
    }

    private func sha256(_ input: String) -> String {
        let hash = SHA256.hash(data: Data(input.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - AuthError

enum AuthError: Error {
    case firebaseError(String)
    case invalidResponse
}

// MARK: - ASAuthorizationControllerDelegate (Sign in with Apple)

extension AuthManager: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData   = credential.identityToken,
              let idTokenStr  = String(data: tokenData, encoding: .utf8),
              let nonce        = currentNonce else { return }

        Task { @MainActor in
            await exchangeAppleToken(idToken: idTokenStr, nonce: nonce,
                                     email: credential.email ?? userEmail)
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                authError = error.localizedDescription
            }
        }
    }

    private func exchangeAppleToken(idToken: String, nonce: String, email: String) async {
        isLoading = true
        defer { isLoading = false }
        // Exchange Apple credential for Firebase session via REST
        let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=\(firebaseApiKey)")!
        let body: [String: Any] = [
            "postBody":          "id_token=\(idToken)&providerId=apple.com&nonce=\(nonce)",
            "requestUri":        "https://accuquote.co.uk",
            "returnIdpCredential": true,
            "returnSecureToken":  true,
        ]
        do {
            let result = try await postFirebase(url: url, body: body)
            let resolvedEmail = (result["email"] as? String) ?? email
            await handleTokenResult(result, email: resolvedEmail)
        } catch {
            authError = friendlyError(error)
        }
    }
}

extension AuthManager: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? UIWindow()
    }
}

// MARK: - SecureTokenStore (Keychain wrapper)

enum SecureTokenStore {
    @discardableResult
    static func write(key: String, value: String) -> Bool {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrAccount as String:      key,
            kSecValueData as String:        data,
            kSecAttrAccessible as String:   kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemDelete(query as CFDictionary)
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func read(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }
}
