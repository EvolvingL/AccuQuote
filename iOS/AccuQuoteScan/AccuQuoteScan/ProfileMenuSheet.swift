import SwiftUI

// MARK: - Profile Menu Sheet
// Persistent profile icon in top-right opens this sheet.
// Three tabs: My Quotes, Update AI Model, Account.

struct ProfileMenuSheet: View {
    @EnvironmentObject var engine: QuestionEngine
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: ProfileTab = .quotes

    enum ProfileTab { case quotes, update, account }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // ── Tab bar ───────────────────────────────────────────────
                HStack(spacing: 0) {
                    tabButton("My Quotes",    icon: "doc.text",      tab: .quotes)
                    tabButton("AI Profile",   icon: "sparkles",      tab: .update)
                    tabButton("Account",      icon: "person.circle", tab: .account)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)

                Divider().background(AQ.rule)

                // ── Content ───────────────────────────────────────────────
                switch selectedTab {
                case .quotes:  QuoteHistoryTab()
                case .update:  AIUpdateTab().environmentObject(engine)
                case .account: AccountTab().environmentObject(engine).environmentObject(EntitlementManager.shared)
                }
            }
            .navigationTitle(tabTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(AQ.secondary)
                }
            }
        }
    }

    private var tabTitle: String {
        switch selectedTab {
        case .quotes:  return "My Quotes"
        case .update:  return "AI Profile"
        case .account: return "Account"
        }
    }

    @ViewBuilder
    private func tabButton(_ label: String, icon: String, tab: ProfileTab) -> some View {
        let active = selectedTab == tab
        Button { withAnimation(.easeInOut(duration: 0.15)) { selectedTab = tab } } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: active ? .semibold : .regular))
                    .accessibilityHidden(true)   // #8
                Text(label)
                    .font(.caption2.weight(active ? .semibold : .regular))   // #1
            }
            .foregroundColor(active ? AQ.blue : AQ.secondary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)   // #2 touch target
            .padding(.vertical, 10)
            .background(active ? AQ.blue.opacity(0.07) : Color.clear)
            .cornerRadius(AQRadius.small)   // #17
        }
        // #27 Large Content Viewer — fixed-size tab text stays usable at large sizes
        .accessibilityShowsLargeContentViewer {
            Label(label, systemImage: icon)
        }
        .accessibilityLabel("\(label) tab\(active ? ", selected" : "")")
    }
}

// MARK: - Quote History Tab

private struct QuoteHistoryTab: View {
    @ObservedObject private var store = QuoteHistoryStore.shared

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        Group {
            if store.quotes.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 44, weight: .light))
                        .foregroundColor(AQ.secondary.opacity(0.4))
                    Text("No quotes yet")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(AQ.ink)
                    Text("Quotes you generate will appear here.")
                        .font(.system(size: 14))
                        .foregroundColor(AQ.secondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(store.quotes) { quote in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("£\(Int(quote.grandTotal).formatted())")
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundColor(AQ.ink)
                                Spacer()
                                Text(dateFormatter.string(from: quote.savedAt))
                                    .font(.system(size: 12))
                                    .foregroundColor(AQ.secondary)
                            }
                            if !quote.customerName.isEmpty {
                                Text(quote.customerName)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(AQ.label)
                                    .lineLimit(1)
                            }
                            Text(quote.jobDescription)
                                .font(.system(size: 13))
                                .foregroundColor(AQ.secondary)
                                .lineLimit(2)
                            HStack(spacing: 8) {
                                Label(quote.roomType.capitalized, systemImage: "cube.transparent")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(AQ.blue)
                                Text("·").foregroundColor(AQ.rule)
                                Text(String(format: "%.1fm²", quote.floorArea))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(AQ.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .onDelete { offsets in
                        for i in offsets { store.delete(id: store.quotes[i].id) }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }
}

// MARK: - AI Profile Update Tab

private struct AIUpdateTab: View {
    @EnvironmentObject var engine: QuestionEngine
    @State private var updateText   = ""
    @State private var isProcessing = false
    @State private var result: UpdateResult? = nil
    @State private var errorMessage: String? = nil
    @FocusState private var inputFocused: Bool

    enum UpdateResult {
        case success(fieldsUpdated: [String])
        case noChange
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // ── Current profile summary ───────────────────────────────
                VStack(alignment: .leading, spacing: 12) {
                    Text("Current profile")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AQ.secondary)
                        .textCase(.uppercase)
                        .kerning(0.6)

                    let answered = engine.questions.filter { $0.isAnswered }
                    if answered.isEmpty {
                        Text("No profile set up yet.")
                            .font(AQ.body(14))
                            .foregroundColor(AQ.secondary)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(answered) { q in
                                HStack(alignment: .top, spacing: 0) {
                                    Text(q.text)
                                        .font(.system(size: 13))
                                        .foregroundColor(AQ.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(q.answer)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(AQ.ink)
                                        .multilineTextAlignment(.trailing)
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 16)
                                if q.id != answered.last?.id {
                                    Divider().background(AQ.rule).padding(.leading, 16)
                                }
                            }
                        }
                        .background(AQ.fill)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AQ.rule, lineWidth: 1))
                    }
                }

                // ── Natural language update ───────────────────────────────
                VStack(alignment: .leading, spacing: 10) {
                    Text("Tell me what's changed")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AQ.secondary)
                        .textCase(.uppercase)
                        .kerning(0.6)

                    Text("Describe changes to your business in plain English. The AI will update the right fields automatically.")
                        .font(AQ.body(13))
                        .foregroundColor(AQ.secondary)
                        .lineSpacing(4)

                    ZStack(alignment: .topLeading) {
                        if updateText.isEmpty {
                            Text("e.g. \"I've put my day rate up to £380, and I've switched from Screwfix to City Plumbing. I also now have an apprentice.\"")
                                .font(AQ.body(14))
                                .foregroundColor(AQ.secondary.opacity(0.6))
                                .padding(.top, 12)
                                .padding(.leading, 16)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $updateText)
                            .font(AQ.body(14))
                            .foregroundColor(AQ.ink)
                            .focused($inputFocused)
                            .frame(minHeight: 110)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    .background(AQ.fill)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(inputFocused ? AQ.blue : AQ.rule, lineWidth: 1.5)
                    )
                }

                // ── Result banner ─────────────────────────────────────────
                if let result = result {
                    switch result {
                    case .success(let fields):
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(AQ.green)
                                .font(.system(size: 18))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Profile updated")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(AQ.green)
                                if !fields.isEmpty {
                                    Text("Updated: \(fields.joined(separator: ", "))")
                                        .font(.system(size: 12))
                                        .foregroundColor(AQ.secondary)
                                }
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AQ.green.opacity(0.08))
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AQ.green.opacity(0.2), lineWidth: 1))

                    case .noChange:
                        HStack(spacing: 10) {
                            Image(systemName: "info.circle")
                                .foregroundColor(AQ.secondary)
                            Text("No profile fields matched what you described. Try being more specific.")
                                .font(.system(size: 13))
                                .foregroundColor(AQ.secondary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AQ.fill)
                        .cornerRadius(10)
                    }
                }

                if let error = errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red)
                        Text(error).font(.system(size: 13)).foregroundColor(.red)
                    }
                    .padding(14)
                    .background(Color.red.opacity(0.06))
                    .cornerRadius(10)
                }

                // ── Submit ────────────────────────────────────────────────
                Button {
                    inputFocused = false
                    Task { await applyUpdate() }
                } label: {
                    Group {
                        if isProcessing {
                            HStack(spacing: 8) {
                                ProgressView().tint(.white)
                                Text("Updating profile…")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                        } else {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 15, weight: .semibold))
                                Text("Update AI profile")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                        }
                    }
                    .foregroundColor(updateText.trimmingCharacters(in: .whitespaces).isEmpty ? AQ.secondary : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(updateText.trimmingCharacters(in: .whitespaces).isEmpty ? AQ.fill : AQ.blue)
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(updateText.trimmingCharacters(in: .whitespaces).isEmpty ? AQ.rule : Color.clear, lineWidth: 1)
                    )
                }
                .disabled(updateText.trimmingCharacters(in: .whitespaces).isEmpty || isProcessing)

                Color.clear.frame(height: 32)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
    }

    @MainActor
    private func applyUpdate() async {
        guard !updateText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isProcessing = true
        result = nil
        errorMessage = nil

        // Build list of current profile fields for Claude to work with
        let currentFields = engine.questions.map { q in
            "id: \(q.id) | question: \(q.text) | current answer: \(q.answer.isEmpty ? "(not answered)" : q.answer)"
        }.joined(separator: "\n")

        let systemPrompt = """
        You are a profile-update assistant for a tradesman quoting app.
        The user will describe changes to their business in plain English.
        You must return a JSON object mapping field IDs to new values.
        Only include fields that the user's message clearly changes.
        If nothing matches, return an empty object {}.

        Available fields:
        \(currentFields)

        Return ONLY valid JSON. Example: {"day_rate": "£350/day", "supplier": "City Plumbing"}
        """

        let userPrompt = "Update my profile based on this: \(updateText)"

        guard let url = URL(string: "\(AQBackend.baseURL)/api/claude") else {
            errorMessage = "Invalid server URL"
            isProcessing = false
            return
        }

        guard let idToken = await AuthManager.shared.currentIdToken() else {
            errorMessage = "Not signed in"
            isProcessing = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "system":     systemPrompt,
            "userPrompt": userPrompt,
            "maxTokens":  512,
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = json["content"] as? String else {
                errorMessage = "Unexpected response from server"
                isProcessing = false
                return
            }

            // Extract JSON from Claude's response
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            let jsonString: String
            if let start = trimmed.range(of: "{"), let end = trimmed.range(of: "}", options: .backwards) {
                jsonString = String(trimmed[start.lowerBound...end.upperBound])
            } else {
                jsonString = trimmed
            }

            guard let updateData = jsonString.data(using: .utf8),
                  let updates = try? JSONSerialization.jsonObject(with: updateData) as? [String: String] else {
                result = .noChange
                isProcessing = false
                return
            }

            if updates.isEmpty {
                result = .noChange
            } else {
                var updatedFields: [String] = []
                for (fieldId, newValue) in updates {
                    if let idx = engine.questions.firstIndex(where: { $0.id == fieldId }) {
                        engine.questions[idx].answer = newValue
                        updatedFields.append(engine.questions[idx].text)
                    }
                }
                engine.saveProfile()
                result = .success(fieldsUpdated: updatedFields)
                updateText = ""
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isProcessing = false
    }
}

// MARK: - Account Tab

private struct AccountTab: View {
    @EnvironmentObject var engine: QuestionEngine
    @EnvironmentObject var entitlement: EntitlementManager
    @State private var showSignOutConfirm  = false
    @State private var showResetConfirm    = false
    @State private var showPaywall         = false
    @State private var resetEmailSent      = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {

                // ── Profile summary card ──────────────────────────────────
                VStack(alignment: .leading, spacing: 12) {
                    let trade  = engine.profile.trade
                    let region = engine.profile.region
                    let biz    = engine.profile.answers.first(where: { $0.id == "business_name" })?.answer ?? ""
                    let email  = AuthManager.shared.userEmail

                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(AQ.blue.opacity(0.1))
                                .frame(width: 52, height: 52)
                            Text(initials(from: biz.isEmpty ? trade : biz))
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(AQ.blue)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(biz.isEmpty ? (trade.isEmpty ? "AccuQuote User" : trade) : biz)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(AQ.ink)
                            if !email.isEmpty {
                                Text(email)
                                    .font(.system(size: 13))
                                    .foregroundColor(AQ.secondary)
                            } else if !region.isEmpty {
                                Text(region)
                                    .font(.system(size: 13))
                                    .foregroundColor(AQ.secondary)
                            }
                            Text("\(engine.personalisation)% profile accuracy")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(AQ.green)
                        }
                        Spacer()
                    }
                }
                .padding(18)
                .background(AQ.fill)
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(AQ.rule, lineWidth: 1))

                // ── Subscription ──────────────────────────────────────────
                VStack(alignment: .leading, spacing: 0) {
                    sectionLabel("Subscription")

                    Button { showPaywall = true } label: {
                        HStack {
                            Image(systemName: entitlement.isPaid ? "checkmark.seal.fill" : "lock.fill")
                                .font(.system(size: 15))
                                .foregroundColor(entitlement.isPaid ? AQ.green : AQ.blue)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entitlement.isPaid ? "\(entitlement.tier.displayName) plan" : "Free plan")
                                    .font(.system(size: 15))
                                    .foregroundColor(AQ.ink)
                                Text(entitlement.isPaid ? entitlement.tier.tagline : "Upgrade to unlock quote generation")
                                    .font(.system(size: 12))
                                    .foregroundColor(AQ.secondary)
                            }
                            Spacer()
                            Text(entitlement.isPaid ? "Manage" : "Upgrade")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(entitlement.isPaid ? AQ.secondary : AQ.blue)
                                .cornerRadius(8)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                }
                .background(Color.white)
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(AQ.rule, lineWidth: 1))

                // ── Security ──────────────────────────────────────────────
                VStack(alignment: .leading, spacing: 0) {
                    sectionLabel("Security")

                    Button {
                        Task {
                            await AuthManager.shared.sendPasswordReset(email: AuthManager.shared.userEmail)
                            resetEmailSent = true
                        }
                    } label: {
                        HStack {
                            Image(systemName: "lock")
                                .font(.system(size: 15))
                                .foregroundColor(AQ.ink)
                                .frame(width: 24)
                            Text(resetEmailSent ? "Reset email sent ✓" : "Change password")
                                .font(.system(size: 15))
                                .foregroundColor(resetEmailSent ? AQ.green : AQ.ink)
                            Spacer()
                            if !resetEmailSent {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                                    .foregroundColor(AQ.secondary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .disabled(AuthManager.shared.userEmail.isEmpty || resetEmailSent)

                    if resetEmailSent {
                        Divider().background(AQ.rule).padding(.leading, 16)
                        Text("Check your email for a link to set a new password.")
                            .font(.system(size: 13))
                            .foregroundColor(AQ.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }
                }
                .background(Color.white)
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(AQ.rule, lineWidth: 1))

                // ── Account actions ───────────────────────────────────────
                VStack(alignment: .leading, spacing: 0) {
                    sectionLabel("Account")

                    Button { showSignOutConfirm = true } label: {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 15))
                                .foregroundColor(.red)
                                .frame(width: 24)
                            Text("Sign out")
                                .font(.system(size: 15))
                                .foregroundColor(.red)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }

                    Divider().background(AQ.rule).padding(.leading, 16)

                    Button { showResetConfirm = true } label: {
                        HStack {
                            Image(systemName: "trash")
                                .font(.system(size: 15))
                                .foregroundColor(.red.opacity(0.7))
                                .frame(width: 24)
                            Text("Reset all profile data")
                                .font(.system(size: 15))
                                .foregroundColor(.red.opacity(0.7))
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                }
                .background(Color.white)
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(AQ.rule, lineWidth: 1))

                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
        .confirmationDialog("Sign out of AccuQuote?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) {
                NotificationCenter.default.post(name: .aqSignOut, object: nil)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your profile and quote history will remain on this device.")
        }
        .confirmationDialog("Reset all profile data?", isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { engine.resetProfile() }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showPaywall) {
            PaywallSheet()
                .environmentObject(entitlement)
                .environmentObject(AuthManager.shared)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(AQ.secondary)
            .textCase(.uppercase)
            .kerning(0.8)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    private func initials(from name: String) -> String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 { return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased() }
        return String(name.prefix(2)).uppercased()
    }
}

// MARK: - Sign out notification

extension Notification.Name {
    static let aqSignOut = Notification.Name("aq_sign_out")
}

// MARK: - Persistent Profile Icon Button

struct ProfileIconButton: View {
    let pct: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(AQ.fill)
                    .frame(width: 36, height: 36)
                    .overlay(Circle().stroke(AQ.rule, lineWidth: 1))

                Image(systemName: "person.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(AQ.ink)

                if pct > 0 {
                    Circle()
                        .fill(pct >= 70 ? AQ.green : AQ.amber)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                        .offset(x: 11, y: -11)
                }
            }
            // #2 expand to 44pt minimum hit target while keeping the 36pt visual
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .accessibilityLabel("Profile and account")   // #8
    }
}
