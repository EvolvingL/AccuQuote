import SwiftUI

// MARK: - Business Verification Gate
//
// Shown by AuthGateView between sign-in and the main app for any account that
// hasn't yet verified a trading name against Companies House. This is a hard
// gate, not a skippable onboarding question (compare TradesmanProfile's
// business_name, which stays optional and feeds quote personalisation) —
// every account must resolve to a real, active UK company/LLP before use.

struct BusinessVerificationView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var verification = BusinessVerificationManager.shared

    @State private var businessName = ""
    // Set when a result is tapped from the live search dropdown — see
    // SignUpView's identical field for why this makes name-matching
    // (missing "Ltd"/"Limited" etc.) a non-issue once the user has picked
    // from the list rather than typed and submitted blind.
    @State private var selectedCompanyNumber: String?
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(AQ.blue.opacity(0.10))
                            .frame(width: 56, height: 56)
                        Image(systemName: "building.2.fill")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(AQ.blue)
                    }
                    .padding(.top, 24)

                    Text("Verify your business")
                        .font(AQ.display(24))
                        .foregroundColor(AQ.ink)

                    Text("AccuQuote is built for registered UK trades businesses. Enter your trading name exactly as registered — we'll check it against Companies House.")
                        .font(.system(size: 14))
                        .foregroundColor(AQ.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, 24)
                }

                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            TextField("Business or trading name", text: $businessName)
                                .textContentType(.organizationName)
                                .autocapitalization(.words)
                                .focused($focused)
                                .submitLabel(.go)
                                .onSubmit { Task { await submit() } }
                                .onChange(of: businessName) { newValue in
                                    selectedCompanyNumber = nil
                                    verification.clearErrorOnly()
                                    verification.search(query: newValue)
                                }
                                .font(.system(size: 16))
                            if selectedCompanyNumber != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(AQ.green)
                            }
                        }
                        .padding(14)
                        .background(AQ.fill)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(focused ? AQ.blue : AQ.rule, lineWidth: 1.5))

                        if focused && selectedCompanyNumber == nil
                            && (!verification.searchResults.isEmpty || verification.isSearching) {
                            VStack(spacing: 0) {
                                if verification.isSearching && verification.searchResults.isEmpty {
                                    HStack {
                                        ProgressView().controlSize(.small)
                                        Text("Searching Companies House…")
                                            .font(.system(size: 13))
                                            .foregroundColor(AQ.secondary)
                                    }
                                    .padding(12)
                                }
                                ForEach(verification.searchResults, id: \.number) { r in
                                    Button {
                                        businessName = r.name
                                        selectedCompanyNumber = r.number
                                        verification.clearSearch()
                                        focused = false
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(r.name)
                                                    .font(.system(size: 14, weight: .medium))
                                                    .foregroundColor(AQ.ink)
                                                Text(r.status.capitalized)
                                                    .font(.system(size: 11))
                                                    .foregroundColor(r.status == "active" ? AQ.green : AQ.secondary)
                                            }
                                            Spacer()
                                        }
                                        .padding(12)
                                        .contentShape(Rectangle())
                                    }
                                    if r.number != verification.searchResults.last?.number {
                                        Divider().background(AQ.rule)
                                    }
                                }
                            }
                            .background(AQ.fill)
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AQ.rule, lineWidth: 1))
                            .padding(.top, 6)
                        }
                    }

                    if let err = verification.lastError {
                        Text(err)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !verification.candidates.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Did you mean:")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AQ.secondary)
                            ForEach(verification.candidates, id: \.number) { c in
                                Button {
                                    businessName = c.name
                                    selectedCompanyNumber = c.number
                                    Task { await submit() }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(c.name)
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(AQ.ink)
                                            Text(c.status.capitalized)
                                                .font(.system(size: 11))
                                                .foregroundColor(AQ.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(AQ.secondary.opacity(0.5))
                                    }
                                    .padding(12)
                                    .background(AQ.fill)
                                    .cornerRadius(10)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            if verification.isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text("Verify business")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(canSubmit ? AQ.blue : AQ.blue.opacity(0.4))
                        .cornerRadius(12)
                    }
                    .disabled(!canSubmit || verification.isLoading)

                    Text("Not registered yet? You'll need an active company or LLP registration to use AccuQuote — this keeps the platform to genuine trades businesses.")
                        .font(.system(size: 12))
                        .foregroundColor(AQ.secondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 28)

                // A fresh sign-up (e.g. Sign in with Apple, which bypasses
                // SignUpView's own inline verify-then-delete-on-abandon flow
                // entirely) abandoning verification here would otherwise leave
                // a real, usable login sitting around with no business
                // attached — so that specific case deletes the account instead
                // of just signing out. A returning user whose verification
                // status lapsed for some other reason is never auto-deleted.
                Button(auth.isFreshSignUp ? "Cancel and delete account" : "Sign out") {
                    Task {
                        if auth.isFreshSignUp {
                            try? await auth.deleteAccount()
                        } else {
                            auth.signOut()
                        }
                        EntitlementManager.shared.clear()
                        verification.clear()
                    }
                }
                .font(.system(size: 13))
                .foregroundColor(auth.isFreshSignUp ? .red : AQ.secondary)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .background(Color.white)
        .onTapGesture { focused = false }
    }

    private var canSubmit: Bool {
        !businessName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func submit() async {
        focused = false
        // Prefer the exact company picked from the search dropdown — no
        // name-matching ambiguity at all. Only falls back to matching by
        // typed name if the user hit "go" without selecting a result.
        if let selectedCompanyNumber {
            await verification.verify(companyNumber: selectedCompanyNumber)
            return
        }
        let name = businessName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        await verification.verify(businessName: name)
    }
}
