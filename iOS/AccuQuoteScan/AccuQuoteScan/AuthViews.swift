import SwiftUI
import AuthenticationServices

// MARK: - Auth Gate

struct AuthGateView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var entitlement: EntitlementManager

    var body: some View {
        Group {
            if auth.isLoading {
                SplashView()
            } else if !auth.isSignedIn {
                LoginView()
            } else {
                ContentView()
                    .task { await entitlement.refresh() }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: auth.isSignedIn)
        .animation(.easeInOut(duration: 0.3), value: auth.isLoading)
    }
}

// MARK: - Splash

private struct SplashView: View {
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "pencil.and.ruler.fill")
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(AQ.blue)
                Text("AccuQuote")
                    .font(AQ.display(28))
                    .foregroundColor(AQ.ink)
            }
        }
    }
}

// MARK: - Login View

struct LoginView: View {
    @EnvironmentObject var auth: AuthManager
    @State private var email = ""
    @State private var password = ""
    @State private var showSignUp = false
    @State private var showReset  = false
    @FocusState private var focusedField: Field?

    enum Field { case email, password }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {

                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "pencil.and.ruler.fill")
                            .font(.system(size: 44, weight: .light))
                            .foregroundColor(AQ.blue)
                        Text("AccuQuote")
                            .font(AQ.display(30))
                            .foregroundColor(AQ.ink)
                        Text("Smart quotes for tradespeople")
                            .font(AQ.body(15))
                            .foregroundColor(AQ.secondary)
                    }
                    .padding(.top, 52)
                    .padding(.bottom, 40)

                    // Form
                    VStack(spacing: 14) {
                        TextField("Email address", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .focused($focusedField, equals: .email)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .password }
                            // Fix #5: clear stale error as user types
                            .onChange(of: email)    { _ in auth.authError = nil }
                            .authField()

                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .focused($focusedField, equals: .password)
                            .submitLabel(.go)
                            .onSubmit { signIn() }
                            .onChange(of: password) { _ in auth.authError = nil }
                            .authField()

                        if let err = auth.authError {
                            Text(err)
                                .font(.system(size: 13))
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                        }

                        Button(action: signIn) {
                            HStack {
                                if auth.isLoading {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Sign in")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(canSubmit ? AQ.blue : AQ.blue.opacity(0.4))
                            .cornerRadius(12)
                        }
                        .disabled(!canSubmit || auth.isLoading)

                        Button("Forgot password?") { showReset = true }
                            .font(.system(size: 14))
                            .foregroundColor(AQ.blue)
                    }
                    .padding(.horizontal, 28)

                    // Divider
                    HStack {
                        Rectangle().fill(AQ.rule).frame(height: 1)
                        Text("or")
                            .font(.system(size: 13))
                            .foregroundColor(AQ.secondary)
                            .padding(.horizontal, 12)
                        Rectangle().fill(AQ.rule).frame(height: 1)
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)

                    // Social sign-in
                    VStack(spacing: 12) {
                        // Fix #4: onCompletion result is ignored by Apple's button — use the
                        // correct pattern: pass the result-less handler and rely on the delegate
                        // (ASAuthorizationControllerDelegate) which auth.signInWithApple() wires up.
                        SignInWithAppleButton(.signIn) { request in
                            request.requestedScopes = [.fullName, .email]
                        } onCompletion: { result in
                            switch result {
                            case .success:
                                // Credential is delivered via ASAuthorizationControllerDelegate
                                // in AuthManager.authorizationController(didCompleteWithAuthorization:)
                                // Nothing to do here — the delegate handles it.
                                break
                            case .failure(let error):
                                let nsErr = error as NSError
                                if nsErr.code != ASAuthorizationError.canceled.rawValue {
                                    auth.authError = error.localizedDescription
                                }
                            }
                        }
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 50)
                        .cornerRadius(12)
                        .padding(.horizontal, 28)
                        // Trigger the native Apple flow when the button is tapped
                        .simultaneousGesture(TapGesture().onEnded { auth.signInWithApple() })

                        // Google Sign-In — fully implemented via ASWebAuthenticationSession
                        SocialButton(
                            label: auth.isLoading ? "Signing in…" : "Sign in with Google",
                            icon: "globe",
                            color: Color(red: 0.85, green: 0.20, blue: 0.15)
                        ) {
                            auth.signInWithGoogle()
                        }
                        .disabled(auth.isLoading)
                        .padding(.horizontal, 28)
                    }

                    // Sign up link
                    HStack(spacing: 4) {
                        Text("Don't have an account?")
                            .font(.system(size: 14))
                            .foregroundColor(AQ.secondary)
                        Button("Sign up") { showSignUp = true }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AQ.blue)
                    }
                    .padding(.top, 28)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showSignUp) { SignUpView() }
        .sheet(isPresented: $showReset)  { PasswordResetView() }
    }

    private var canSubmit: Bool { !email.isEmpty && password.count >= 6 }

    private func signIn() {
        guard canSubmit else { return }
        focusedField = nil
        Task { await auth.signIn(email: email, password: password) }
    }
}

// MARK: - Sign Up View

struct SignUpView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var didDismiss = false   // Fix #6: guard against double-dismiss
    @FocusState private var focusedField: Field?

    enum Field { case email, password, confirm }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    Text("Create your account")
                        .font(AQ.display(24))
                        .foregroundColor(AQ.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)

                    VStack(spacing: 14) {
                        TextField("Email address", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .focused($focusedField, equals: .email)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .password }
                            .onChange(of: email) { _ in auth.authError = nil }
                            .authField()

                        SecureField("Password (min 6 characters)", text: $password)
                            .textContentType(.newPassword)
                            .focused($focusedField, equals: .password)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .confirm }
                            .onChange(of: password) { _ in auth.authError = nil }
                            .authField()

                        SecureField("Confirm password", text: $confirm)
                            .textContentType(.newPassword)
                            .focused($focusedField, equals: .confirm)
                            .submitLabel(.go)
                            .onSubmit { signUp() }
                            .authField()

                        if let err = auth.authError {
                            Text(err)
                                .font(.system(size: 13))
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if !confirm.isEmpty && password != confirm {
                            Text("Passwords don't match")
                                .font(.system(size: 13))
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button(action: signUp) {
                            HStack {
                                if auth.isLoading {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Create account")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(canSubmit ? AQ.blue : AQ.blue.opacity(0.4))
                            .cornerRadius(12)
                        }
                        .disabled(!canSubmit || auth.isLoading)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 40)
            }
            .navigationTitle("Sign Up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        didDismiss = true
                        dismiss()
                    }
                    .foregroundColor(AQ.secondary)
                }
            }
        }
        // Fix #6: guard prevents double-dismiss when isSignedIn flips while Cancel is mid-animation
        .onChange(of: auth.isSignedIn) { signed in
            if signed && !didDismiss {
                didDismiss = true
                dismiss()
            }
        }
    }

    private var canSubmit: Bool {
        !email.isEmpty && password.count >= 6 && password == confirm
    }

    private func signUp() {
        guard canSubmit else { return }
        focusedField = nil
        Task { await auth.signUp(email: email, password: password) }
    }
}

// MARK: - Password Reset View

struct PasswordResetView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var email   = ""
    @State private var sent    = false
    @State private var loading = false   // Fix #3: prevent double-tap
    @State private var resetError: String? = nil  // Fix #2: show real network/server errors

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Text("We'll send a reset link to your email address.")
                    .font(AQ.body(15))
                    .foregroundColor(AQ.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                TextField("Email address", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .onChange(of: email) { _ in resetError = nil; sent = false }
                    .authField()

                if sent {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(AQ.green)
                        Text("Reset email sent — check your inbox.")
                            .font(.system(size: 14))
                            .foregroundColor(AQ.green)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Fix #2: show error if the reset call actually fails
                if let err = resetError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red)
                        Text(err).font(.system(size: 14)).foregroundColor(.red)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button("Send reset link") {
                    guard !loading else { return }  // Fix #3: debounce
                    loading = true
                    Task {
                        defer { loading = false }
                        do {
                            try await auth.sendPasswordReset(email: email, onError: { err in
                                resetError = err
                            })
                            sent = true
                        } catch {
                            resetError = error.localizedDescription
                        }
                    }
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(email.isEmpty || loading ? AQ.blue.opacity(0.4) : AQ.blue)
                .cornerRadius(12)
                .disabled(email.isEmpty || loading)
                .overlay {
                    if loading { ProgressView().tint(.white) }
                }

                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .navigationTitle("Reset Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundColor(AQ.secondary)
                }
            }
        }
    }
}

// MARK: - Paywall Sheet

struct PaywallSheet: View {
    @EnvironmentObject var entitlement: EntitlementManager
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedInterval: PayInterval = .monthly
    @State private var isLoading = false
    @State private var error: String?

    enum PayInterval: String, CaseIterable {
        case monthly = "Monthly"
        case annual  = "Annual"
        var saving: String? { self == .annual ? "Save 17%" : nil }
    }

    private let tiers: [(tier: EntitlementManager.SubscriptionTier, icon: String)] = [
        (.solo, "person.fill"),
        (.team, "person.2.fill"),
        (.crew, "person.3.fill"),
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 28) {

                    VStack(spacing: 8) {
                        Image(systemName: "lock.open.fill")
                            .font(.system(size: 36, weight: .light))
                            .foregroundColor(AQ.blue)
                        Text("Unlock AccuQuote Pro")
                            .font(AQ.display(24))
                            .foregroundColor(AQ.ink)
                        Text("Generate detailed, AI-powered quotes with real material pricing")
                            .font(AQ.body(14))
                            .foregroundColor(AQ.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    // Monthly / annual toggle
                    HStack(spacing: 0) {
                        ForEach(PayInterval.allCases, id: \.self) { interval in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { selectedInterval = interval }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(interval.rawValue)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(selectedInterval == interval ? .white : AQ.secondary)
                                    if let saving = interval.saving {
                                        Text(saving)
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(selectedInterval == interval ? .white.opacity(0.85) : AQ.green)
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(selectedInterval == interval ? Color.white.opacity(0.2) : AQ.green.opacity(0.12))
                                            .cornerRadius(6)
                                    }
                                }
                                .frame(maxWidth: .infinity).frame(height: 38)
                                .background(selectedInterval == interval ? AQ.blue : Color.clear)
                                .cornerRadius(9)
                            }
                        }
                    }
                    .padding(3)
                    .background(AQ.fill).cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(AQ.rule, lineWidth: 1))
                    .padding(.horizontal, 24)

                    // Tier cards
                    VStack(spacing: 12) {
                        ForEach(tiers, id: \.tier) { item in
                            TierCard(
                                tier: item.tier, icon: item.icon,
                                interval: selectedInterval,
                                isCurrentTier: entitlement.tier == item.tier
                            ) { subscribe(tier: item.tier) }
                        }
                    }
                    .padding(.horizontal, 24)

                    // Free tier note
                    VStack(spacing: 6) {
                        Text("Free tier includes")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AQ.secondary)
                            .textCase(.uppercase).kerning(0.5)
                        Text("Room scanning · Floor area · Wall dimensions")
                            .font(AQ.body(13))
                            .foregroundColor(AQ.secondary)
                    }
                    .padding(.vertical, 16).frame(maxWidth: .infinity)
                    .background(AQ.fill).cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(AQ.rule, lineWidth: 1))
                    .padding(.horizontal, 24)

                    if let err = error {
                        Text(err)
                            .font(.system(size: 13)).foregroundColor(.red)
                            .padding(.horizontal, 24)
                    }

                    Color.clear.frame(height: 20)
                }
            }
            .navigationTitle("Plans")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }.foregroundColor(AQ.secondary)
                }
            }
        }
    }

    private func subscribe(tier: EntitlementManager.SubscriptionTier) {
        // Fix #1: removed the dead `auth.userId.isEmpty ? nil : auth.userId` guard
        // which was tautological. We rely solely on currentIdToken() below.
        guard !isLoading else { return }
        isLoading = true
        error = nil
        Task {
            defer { isLoading = false }
            guard let idToken = await AuthManager.shared.currentIdToken() else {
                error = "Authentication error. Please sign in again."
                return
            }
            guard let url = URL(string: "\(AQBackend.baseURL)/api/stripe/create-checkout") else {
                error = "Invalid server URL."
                return
            }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
            req.httpBody = try? JSONSerialization.data(withJSONObject: [
                "tier": tier.rawValue,
                "interval": selectedInterval == .monthly ? "month" : "year",
            ])

            guard let (data, response) = try? await URLSession.shared.data(for: req) else {
                error = "Network error. Please check your connection."
                return
            }
            let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                error = json["error"] as? String ?? "Could not create checkout session (\(http.statusCode))."
                return
            }
            guard let checkoutURL = json["url"] as? String,
                  let openURL = URL(string: checkoutURL)
            else {
                error = "Could not create checkout session. Please try again."
                return
            }
            await UIApplication.shared.open(openURL)
        }
    }
}

// MARK: - Tier Card

private struct TierCard: View {
    let tier: EntitlementManager.SubscriptionTier
    let icon: String
    let interval: PaywallSheet.PayInterval
    let isCurrentTier: Bool
    let onSubscribe: () -> Void

    var price: String { interval == .monthly ? tier.monthlyPrice : tier.annualPrice }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AQ.blue)
                    .frame(width: 32, height: 32)
                    .background(AQ.blue.opacity(0.1))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(tier.displayName)
                        .font(.system(size: 16, weight: .semibold)).foregroundColor(AQ.ink)
                    Text(tier.tagline)
                        .font(.system(size: 13)).foregroundColor(AQ.secondary)
                }
                Spacer()
                Text(price)
                    .font(.system(size: 15, weight: .bold)).foregroundColor(AQ.blue)
            }

            Button(action: onSubscribe) {
                Text(isCurrentTier ? "Current plan" : "Subscribe")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(isCurrentTier ? AQ.secondary : .white)
                    .frame(maxWidth: .infinity).frame(height: 42)
                    .background(isCurrentTier ? AQ.fill : AQ.blue)
                    .cornerRadius(10)
            }
            .disabled(isCurrentTier)
        }
        .padding(18).background(Color.white).cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(isCurrentTier ? AQ.blue.opacity(0.4) : AQ.rule,
                    lineWidth: isCurrentTier ? 2 : 1))
    }
}

// MARK: - Locked Result View

struct LockedResultView: View {
    let result: RoomDimensions
    @ObservedObject var coordinator: ScanCoordinator
    @State private var showPaywall = false

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 20) {
                    DimensionsSummaryCard(result: result)
                        .padding(.horizontal, 20).padding(.top, 24)

                    VStack(spacing: 16) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 32, weight: .light))
                            .foregroundColor(AQ.secondary.opacity(0.4))
                        Text("Quote generation is a Pro feature")
                            .font(AQ.title(17)).foregroundColor(AQ.ink).multilineTextAlignment(.center)
                        Text("Upgrade to generate AI-powered quotes with real material pricing, PDF export, and quote history.")
                            .font(AQ.body(14)).foregroundColor(AQ.secondary)
                            .multilineTextAlignment(.center).padding(.horizontal, 16)
                        Button("See plans") { showPaywall = true }
                            .font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .background(AQ.blue).cornerRadius(12).padding(.horizontal, 4)
                    }
                    .padding(24).background(AQ.fill).cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(AQ.rule, lineWidth: 1))
                    .padding(.horizontal, 20)

                    Button { coordinator.reset() } label: {
                        Text("Scan again").font(.system(size: 15)).foregroundColor(AQ.secondary)
                    }
                    .padding(.bottom, 32)
                }
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallSheet()
                .environmentObject(EntitlementManager.shared)
                .environmentObject(AuthManager.shared)
        }
    }
}

// MARK: - Dimensions Summary Card

struct DimensionsSummaryCard: View {
    let result: RoomDimensions

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(result.roomType.capitalized)
                .font(AQ.display(20)).foregroundColor(AQ.ink)

            HStack(spacing: 0) {
                dimensionItem(label: "Length", value: result.lengthStr + "m")
                Divider().frame(height: 32)
                dimensionItem(label: "Width",  value: result.widthStr  + "m")
                Divider().frame(height: 32)
                dimensionItem(label: "Height", value: result.heightStr + "m")
            }
            .frame(maxWidth: .infinity)

            HStack {
                Label(String(format: "%.1fm² floor", result.floorArea), systemImage: "square.dashed")
                    .font(.system(size: 13, weight: .medium)).foregroundColor(AQ.blue)
                Spacer()
                Label(String(format: "%.1fm² walls", result.wallArea), systemImage: "rectangle.3.group")
                    .font(.system(size: 13, weight: .medium)).foregroundColor(AQ.secondary)
            }
        }
        .padding(18).background(Color.white).cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AQ.rule, lineWidth: 1))
    }

    private func dimensionItem(label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 18, weight: .bold, design: .rounded)).foregroundColor(AQ.ink)
            Text(label).font(.system(size: 11)).foregroundColor(AQ.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Social button

private struct SocialButton: View {
    let label: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 18)).foregroundColor(color)
                Text(label).font(.system(size: 15, weight: .medium)).foregroundColor(AQ.ink)
            }
            .frame(maxWidth: .infinity).frame(height: 50)
            .background(AQ.fill).cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AQ.rule, lineWidth: 1))
        }
    }
}

// MARK: - Auth field style

private extension View {
    func authField() -> some View {
        self
            .font(.system(size: 16))
            .padding(14)
            .background(AQ.fill)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AQ.rule, lineWidth: 1.5))
    }
}
