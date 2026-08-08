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
    // Web API key — safe to include in the app (identifies project, not a secret).
    // Must match the "accuquoteprod" Firebase project (com.accuquote1.scan) —
    // see GoogleService-Info (1).plist's API_KEY. The old key here belonged to
    // the pre-rename Firebase project and silently sent every Auth REST call
    // (signInWithPassword/signUp/signInWithIdp/token refresh) to the wrong
    // project, which correctly rejected the new Google OAuth client as
    // unauthorized (INVALID_IDP_RESPONSE).
    private let firebaseApiKey = "AIzaSyDXG5NMqjZzC4mI2MYtgLclxEBBbY55kRM"
    private var idToken: String? = nil
    private var refreshToken: String? = nil
    private var tokenExpiry: Date = .distantPast
    // R4: coalesces concurrent refreshes into one in-flight request so parallel
    // section/entitlement/Stripe calls don't trigger N simultaneous token rotations
    // (which would invalidate each other and silently sign the user out).
    private var refreshInFlight: Task<Bool, Never>? = nil

    // MARK: - Keychain keys
    private let keychainIdToken      = "aq_firebase_id_token"
    private let keychainRefreshToken = "aq_firebase_refresh_token"
    private let keychainUserId       = "aq_firebase_user_id"
    private let keychainEmail        = "aq_firebase_email"

    // MARK: - Apple Sign-In nonce
    // nonisolated(unsafe) allows the nonisolated delegate to read this safely
    nonisolated(unsafe) private var currentNonce: String?

    // MARK: - Referral code carried into sign-up
    //
    // Set by LoginView just before starting ANY sign-up path (email/password
    // via SignUpView, or tapping Apple/Google directly on LoginView, both of
    // which can create a brand-new account with no separate "sign up" step).
    // Read once inside handleTokenResult when that call turns out to be a
    // genuine new-account creation (isNewUser), then cleared — never applied
    // to a sign-IN of an existing account, and never applied twice.
    var pendingReferralCode: String? = nil

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
        // Attempt to get a fresh ID token. Only sign the user out if the server
        // explicitly rejects the refresh token (revoked/expired) — a transient
        // network failure (offline launch, server hiccup) must NOT wipe the
        // session, or every user who opens the app without signal gets logged out.
        switch await performRefreshDetailed() {
        case .success:
            isSignedIn = true
        case .invalidToken:
            clearLocalSession()
        case .transientFailure:
            // Keep the stored session; treat as signed-in optimistically. The next
            // authenticated API call will refresh again once connectivity returns.
            isSignedIn = true
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
    // Throws on network failure or Firebase error so the caller can show a real error.
    // Fix: was swallowing all errors silently — users saw "Sent" even when it failed.

    func sendPasswordReset(email: String, onError: ((String) -> Void)? = nil) async throws {
        let url  = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=\(firebaseApiKey)")!
        let body: [String: Any] = ["requestType": "PASSWORD_RESET", "email": email]
        do {
            _ = try await postFirebase(url: url, body: body)
        } catch {
            let msg = friendlyError(error)
            onError?(msg)
            throw error
        }
    }

    // MARK: - Delete account
    //
    // Permanently deletes the Firebase Auth user via accounts:delete. Firebase
    // requires a *recent* login for this — a token that's still valid but was
    // issued a while ago gets rejected with CREDENTIAL_TOO_OLD_LOGIN_AGAIN.
    // Rather than building a full re-auth UI here, surface a friendly message
    // via friendlyError() directing the user to sign out and back in, then retry.
    //
    // Note: this only deletes the Firebase Auth account. Any server-side data
    // AQBackend holds for this user (quotes, profile, etc.) is NOT deleted by
    // this call — there is no existing authenticated-DELETE endpoint on the
    // backend for that today, so this is scoped to the Auth account only.
    // Backend data cleanup would need its own API surface designed separately.
    func deleteAccount(onError: ((String) -> Void)? = nil) async throws {
        guard let token = await currentIdToken() else {
            let msg = "Please sign in again before deleting your account."
            onError?(msg)
            throw AuthError.invalidResponse
        }
        let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:delete?key=\(firebaseApiKey)")!
        let body: [String: Any] = ["idToken": token]
        do {
            _ = try await postFirebase(url: url, body: body)
            clearLocalSession()
        } catch {
            let msg = friendlyError(error)
            onError?(msg)
            throw error
        }
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

    // MARK: - Sign in with Google
    //
    // Uses ASWebAuthenticationSession to open Google's OAuth 2.0 consent screen.
    // The returned authorization code is exchanged for tokens at Google's token endpoint,
    // then the id_token is exchanged for a Firebase session via signInWithIdp.
    //
    // Client ID comes from the Firebase Console → Project Settings → Your apps → iOS app
    // → Download GoogleService-Info.plist → CLIENT_ID field.
    // It is safe to bundle in the app — it is public.
    //
    // Required: Add the reversed client ID as a URL scheme in Info.plist:
    //   CFBundleURLSchemes: com.googleusercontent.apps.<CLIENT_ID_WITHOUT_APPS_PREFIX>
    // (Xcode: project → Signing & Capabilities → Info → URL Types)

    // CLIENT_ID from GoogleService-Info.plist, WITHOUT the trailing
    // ".apps.googleusercontent.com" — the code appends that suffix where needed
    // (see signInWithGoogle / the token exchange) and uses the reversed form
    // "com.googleusercontent.apps.<id>" as the OAuth callback URL scheme, which
    // is registered in Info.plist.
    private let googleClientID = "912087276302-6b5fgur3mm2a0gkrs7ok38dfdc2egd9k"

    func signInWithGoogle() {
        authError = nil
        isLoading = true

        let clientID    = googleClientID
        let redirectURI = "com.googleusercontent.apps.\(clientID):/oauth2callback"
        let nonce       = randomNonceString()
        let hashedNonce = sha256(nonce)

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id",     value: "\(clientID).apps.googleusercontent.com"),
            URLQueryItem(name: "redirect_uri",  value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope",         value: "openid email profile"),
            URLQueryItem(name: "nonce",         value: hashedNonce),
            URLQueryItem(name: "prompt",        value: "select_account"),
        ]

        guard let authURL = components.url else {
            authError = "Failed to build Google sign-in URL."
            isLoading = false
            return
        }

        let scheme  = "com.googleusercontent.apps.\(clientID)"
        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: scheme
        ) { [weak self] callbackURL, error in
            guard let self else { return }
            Task { @MainActor in
                defer { self.isLoading = false }

                if let error {
                    let nsErr = error as NSError
                    // User cancelled — not an error worth showing
                    if nsErr.code == ASWebAuthenticationSessionError.canceledLogin.rawValue { return }
                    self.authError = error.localizedDescription
                    return
                }

                guard let callbackURL,
                      let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                          .queryItems?.first(where: { $0.name == "code" })?.value
                else {
                    self.authError = "Google sign-in did not return an authorisation code."
                    return
                }

                await self.exchangeGoogleCode(code, redirectURI: redirectURI, nonce: nonce)
            }
        }
        session.presentationContextProvider = self
        // Fix #25: ephemeral session prevents Google cookies persisting across users
        // on a shared device after the user signs out of AccuQuote.
        session.prefersEphemeralWebBrowserSession = true
        session.start()
    }

    private func exchangeGoogleCode(_ code: String, redirectURI: String, nonce: String) async {
        // Exchange authorisation code → id_token at Google token endpoint
        let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let params: [String: String] = [
            "code":          code,
            "client_id":     "\(googleClientID).apps.googleusercontent.com",
            "redirect_uri":  redirectURI,
            "grant_type":    "authorization_code",
        ]
        req.httpBody = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let idToken = json["id_token"] as? String
        else {
            authError = "Failed to get Google credentials. Please try again."
            return
        }

        // Exchange Google id_token → Firebase session
        let fbURL = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=\(firebaseApiKey)")!
        let body: [String: Any] = [
            "postBody":          "id_token=\(idToken)&providerId=google.com&nonce=\(nonce)",
            "requestUri":        "https://accuquote.uk",
            "returnIdpCredential": true,
            "returnSecureToken":  true,
        ]
        do {
            let result = try await postFirebase(url: fbURL, body: body)
            let email = (result["email"] as? String) ?? ""
            await handleTokenResult(result, email: email)
        } catch {
            authError = friendlyError(error)
        }
    }

    // MARK: - Sign out

    // Does NOT post .aqSignOut — this is only ever called *in response* to
    // that notification (ContentView's .onReceive(.aqSignOut) below calls
    // this). Posting it here too was an infinite loop: post → ContentView's
    // handler calls signOut() → signOut() posts again → forever, which froze
    // the app on sign-out. The notification is the trigger; this is the effect.
    func signOut() {
        clearLocalSession()
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

        // Firebase's isNewUser is present on accounts:signUp / signInWithIdp
        // responses; absent (nil) on plain signInWithPassword — default false
        // there since a password sign-in is by definition an existing account.
        // Every one of the 4 auth paths (email/password sign-up, Apple,
        // Google, and — harmlessly, since isNewUser is false there — plain
        // sign-in) converges on this one function, so this is the single
        // choke point for "did this call just create a brand-new account."
        let isNewUser = (result["isNewUser"] as? Bool) ?? false
        registerPendingReferralIfNeeded(isNewUser: isNewUser)
    }

    /// Fires (fire-and-forget) the one-time referral-code registration for a
    /// freshly-created account, if the user entered one on LoginView before
    /// starting this sign-up. Deliberately non-blocking and non-throwing —
    /// see ReferralService.register's own doc comment for why a broken code
    /// must never affect the sign-up itself.
    private func registerPendingReferralIfNeeded(isNewUser: Bool) {
        guard isNewUser, let code = pendingReferralCode, !code.isEmpty else {
            pendingReferralCode = nil
            return
        }
        pendingReferralCode = nil
        Task {
            let ok = await ReferralService.register(code: code)
            if !ok {
                AQLog.referral.warning("registerPendingReferralIfNeeded: registration did not succeed (code invalid, already used, or network failure) — account creation was not affected")
            }
        }
    }

    @discardableResult
    private func refreshIdToken() async -> Bool {
        // R4: if a refresh is already running, await its result instead of starting
        // a second one. This dedups the token-rotation stampede.
        if let inFlight = refreshInFlight {
            return await inFlight.value
        }
        let task = Task { @MainActor in await self.performRefresh() }
        refreshInFlight = task
        let result = await task.value
        refreshInFlight = nil
        return result
    }

    /// Outcome of a token refresh attempt — lets callers tell a genuinely
    /// revoked/expired refresh token (must sign out) apart from a transient
    /// network problem (keep the session and retry later).
    private enum RefreshOutcome {
        case success
        case invalidToken       // server rejected the refresh token (4xx) — sign out
        case transientFailure   // offline / timeout / 5xx / malformed — keep session
    }

    private func performRefresh() async -> Bool {
        if case .success = await performRefreshDetailed() { return true }
        return false
    }

    private func performRefreshDetailed() async -> RefreshOutcome {
        guard let refresh = refreshToken, !refresh.isEmpty else { return .invalidToken }
        let url = URL(string: "https://securetoken.googleapis.com/v1/token?key=\(firebaseApiKey)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = "grant_type=refresh_token&refresh_token=\(refresh)".data(using: .utf8)

        // A thrown error here is a transport failure (offline, timeout, DNS) —
        // never a reason to destroy the session.
        guard let (data, response) = try? await URLSession.shared.data(for: req) else {
            return .transientFailure
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // 400/401/403 from Google's secure-token endpoint means the refresh token
        // is invalid/revoked. 5xx and anything else are transient.
        if (400...499).contains(status) { return .invalidToken }
        guard status == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token   = json["id_token"]      as? String,
              let newRefresh = json["refresh_token"] as? String else {
            return .transientFailure
        }

        let expiresIn = TimeInterval(json["expires_in"] as? String ?? "3600") ?? 3600
        idToken      = token
        refreshToken = newRefresh
        tokenExpiry  = Date().addingTimeInterval(expiresIn)
        SecureTokenStore.write(key: keychainIdToken,      value: token)
        SecureTokenStore.write(key: keychainRefreshToken, value: newRefresh)
        return .success
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
                case "EMAIL_NOT_FOUND":          return "No account found with that email. Tap \"Sign up\" below to create one."
                case "INVALID_PASSWORD":         return "Incorrect password."
                // Modern Firebase projects return this consolidated code instead of
                // EMAIL_NOT_FOUND/INVALID_PASSWORD specifically to prevent sign-in
                // enumeration (an attacker learning which emails have accounts) — so
                // this case covers BOTH "no account exists" and "wrong password" and
                // can't honestly claim to know which. Points at the existing "Sign up"
                // link either way rather than guessing.
                case "INVALID_LOGIN_CREDENTIALS": return "Incorrect email or password. If you don't have an account yet, tap \"Sign up\" below."
                case "EMAIL_EXISTS":             return "An account already exists with that email."
                case "WEAK_PASSWORD : Password should be at least 6 characters":
                                                 return "Password must be at least 6 characters."
                case "INVALID_EMAIL":            return "Please enter a valid email address."
                case "TOO_MANY_ATTEMPTS_TRY_LATER": return "Too many attempts. Please try again later."
                case "CREDENTIAL_TOO_OLD_LOGIN_AGAIN", "TOKEN_EXPIRED":
                                                 return "For your security, please sign out and sign back in before doing this."
                // Fix #11 — previously fell through to `msg`, i.e. Firebase's raw
                // internal error code (e.g. "OPERATION_NOT_ALLOWED",
                // "USER_DISABLED") shown verbatim to the user. Any code not
                // explicitly recognised above now gets a generic, still-actionable
                // message instead of framework internals.
                default:
                    AQLog.auth.warning("Unrecognised Firebase error code: \(msg, privacy: .public)")
                    return "Something went wrong. Please try again."
                }
            case .invalidResponse: return "Unexpected response. Please try again."
            }
        }
        // Fix #11 — same reasoning as the switch's default case above: a raw
        // NSError.localizedDescription (from network/URLSession failures, not
        // Firebase's own error JSON) is a developer-facing string, not
        // something to show the user as-is.
        return "Something went wrong. Please try again."
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
        // Consume the nonce immediately so it can't be reused by a subsequent
        // Sign-in-with-Apple attempt (a fresh nonce is generated per request).
        currentNonce = nil

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
            "requestUri":        "https://accuquote.uk",
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

extension AuthManager: ASAuthorizationControllerPresentationContextProviding,
                       ASWebAuthenticationPresentationContextProviding {

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        keyWindow()
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        keyWindow()
    }

    private nonisolated func keyWindow() -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? UIWindow()
    }
}

// MARK: - SecureTokenStore (Keychain wrapper)

enum SecureTokenStore {
    // Fix #10: the long-lived refresh token must use WhenUnlocked so it is only
    // accessible while the screen is actively unlocked — not in background on first-unlock.
    // Short-lived ID tokens can use AfterFirstUnlock for background refresh.
    private static let sensitiveKeys: Set<String> = [
        "aq_firebase_refresh_token",   // permanent credential — highest protection
        "aq_apns_token",               // device identity token
    ]

    @discardableResult
    static func write(key: String, value: String) -> Bool {
        let data        = Data(value.utf8)
        let accessible  = sensitiveKeys.contains(key)
            ? kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrAccount as String:      key,
            kSecValueData as String:        data,
            kSecAttrAccessible as String:   accessible,
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
