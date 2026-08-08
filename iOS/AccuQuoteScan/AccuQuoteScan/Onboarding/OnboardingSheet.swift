import SwiftUI

// MARK: - AI Profile button

struct AIProfileButton: View {
    let answered: Int
    let pct: Int
    let action: () -> Void
    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                // Pulsing orb
                ZStack {
                    Circle()
                        .fill(answered > 0 ? AQ.green.opacity(0.12) : AQ.blue.opacity(0.12))
                        .frame(width: 22, height: 22)
                        .scaleEffect(pulse ? 1.22 : 1.0)
                        .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: pulse)
                    if answered > 0 {
                        Circle()
                            .trim(from: 0, to: CGFloat(pct) / 100)
                            .stroke(AQ.green, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                            .frame(width: 14, height: 14)
                            .rotationEffect(.degrees(-90))
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(AQ.blue)
                    }
                }
                .onAppear { pulse = true }

                if answered > 0 {
                    Text("\(pct)% complete")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AQ.green)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.3), value: pct)
                } else {
                    Text("Set up AI")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AQ.blue)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(minHeight: 44)   // #2 touch target
            .background(
                RoundedRectangle(cornerRadius: AQRadius.xxl)   // #17
                    .stroke(answered > 0 ? AQ.green.opacity(0.3) : AQ.blue.opacity(0.3), lineWidth: 1)
            )
        }
        .accessibilityLabel(answered > 0 ? "AI profile, \(pct) percent complete. Tap to edit."
                                         : "Set up AI profile")   // #8
    }
}

// MARK: - Accuracy Pill (onboarding header)

struct AccuracyPill: View {
    let pct: Int
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(pct > 0 ? AQ.green.opacity(0.1) : AQ.blue.opacity(0.1))
                    .frame(width: 16, height: 16)
                    .scaleEffect(pulse ? 1.3 : 1.0)
                    .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: pulse)
                Circle()
                    .fill(pct > 0 ? AQ.green : AQ.blue)
                    .frame(width: 6, height: 6)
            }
            .onAppear { pulse = true }

            Text(pct > 0 ? "\(pct)% profile complete" : "Not set up")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(pct > 0 ? AQ.green : AQ.secondary)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.3), value: pct)
        }
    }
}

// MARK: - Scan Method Badge

struct ScanMethodBadge: View {
    let method: ScanMethod
    var color: Color {
        switch method {
        case .lidar:      return AQ.green
        case .poseFusion: return AQ.blue
        case .manual:     return AQ.green
        }
    }
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(method.displayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(color.opacity(0.08))
        .cornerRadius(20)
    }
}


// MARK: - Onboarding Sheet

struct OnboardingSheet: View {
    @EnvironmentObject var engine: QuestionEngine
    @Environment(\.dismiss) var dismiss
    @State private var inputText = ""
    @State private var selectedTab: OnboardingTab = .questions
    @State private var showDocumentPicker = false
    @State private var showAddDocumentSheet = false
    @FocusState private var inputFocused: Bool

    enum OnboardingTab { case questions, documents }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // ── Progress bar ────────────────────────────────────────────
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(AQ.rule)
                        Rectangle()
                            .fill(AQ.blue)
                            .frame(width: geo.size.width * CGFloat(engine.progress))
                            .animation(.easeInOut(duration: 0.4), value: engine.progress)
                    }
                }
                .frame(height: 2)

                // ── Stats row ───────────────────────────────────────────────
                HStack {
                    HStack(spacing: 6) {
                        Text("\(engine.answeredCount) answered")
                            .font(AQ.body(12))
                            .foregroundColor(AQ.secondary)
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.3), value: engine.answeredCount)
                        // #26: show how many questions remain so users understand the flow length
                        let remaining = max(0, engine.questions.count - engine.answeredCount)
                        if remaining > 0 {
                            Text("· \(remaining) to go")
                                .font(AQ.body(12))
                                .foregroundColor(AQ.secondary.opacity(0.7))
                        }
                        if engine.isGeneratingMore {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.5)
                                    .tint(AQ.blue)
                                Text("learning…")
                                    .font(.caption2)   // #1
                                    .foregroundColor(AQ.blue)
                            }
                        }
                    }
                    Spacer()
                    AccuracyPill(pct: engine.personalisation)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)

                // ── Tab picker ──────────────────────────────────────────────
                HStack(spacing: 0) {
                    TabPill(label: "Questions", icon: "bubble.left",
                            active: selectedTab == .questions,
                            badge: engine.questions.filter { !$0.isAnswered }.count)
                    { selectedTab = .questions }

                    TabPill(label: "Documents", icon: "doc.text",
                            active: selectedTab == .documents,
                            badge: engine.profile.documents.count)
                    { selectedTab = .documents }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 4)

                Divider().background(AQ.rule)

                // ── Content ─────────────────────────────────────────────────
                if selectedTab == .questions {
                    questionContent
                } else {
                    documentContent
                }
            }
            .background(Color.white)
            .navigationTitle("AI Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AQ.blue)
                }
            }
        }
        .onTapGesture { inputFocused = false }
        .sheet(isPresented: $showAddDocumentSheet) {
            AddDocumentSheet(engine: engine)
        }
    }

    // MARK: - Questions tab

    @ViewBuilder var questionContent: some View {
        // #21: ScrollViewReader auto-scrolls the active question into view when it
        // changes, so the keyboard never hides the input the user is answering.
        ScrollViewReader { proxy in
        ScrollView {
            VStack(spacing: 0) {
                if let question = engine.currentQuestion {
                    // Explanation banner at top
                    if engine.answeredCount == 0 {
                        WelcomeBanner()
                            .padding(.horizontal, 24)
                            .padding(.top, 20)
                            .padding(.bottom, 16)
                    }

                    QuestionCard(
                        question: question,
                        inputText: $inputText,
                        inputFocused: $inputFocused,
                        onSubmit: {
                            guard !inputText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                engine.submitAnswer(inputText)
                                inputText = ""
                            }
                        },
                        onSkip: {
                            withAnimation { engine.skipCurrent() }
                            inputText = ""
                        }
                    )
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal:   .move(edge: .leading).combined(with: .opacity)
                    ))
                    .id(question.id)

                } else if engine.isGeneratingMore {
                    // Generating next batch
                    VStack(spacing: 14) {
                        ProgressView().tint(AQ.blue)
                        Text("Preparing more questions…")
                            .font(AQ.body(14))
                            .foregroundColor(AQ.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(48)
                } else {
                    // Temporarily caught up — nudge toward documents
                    CaughtUpCard {
                        selectedTab = .documents
                        showAddDocumentSheet = true
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                }

                // Previously answered questions (collapsed, reviewable)
                if engine.answeredCount > 0 {
                    AnsweredReviewSection(questions: engine.questions.filter { $0.isAnswered })
                        .padding(.top, 32)
                        .padding(.horizontal, 24)
                }

                Color.clear.frame(height: 40)
            }
        }
        // #21: scroll the current question to the top when it advances
        .onChange(of: engine.currentQuestion?.id) { newID in
            if let id = newID {
                withAnimation { proxy.scrollTo(id, anchor: .top) }
            }
        }
        }
    }

    // MARK: - Documents tab

    @ViewBuilder var documentContent: some View {
        ScrollView {
            VStack(spacing: 0) {

                DocumentsExplainerBanner()
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 16)

                // Upload button
                Button { showAddDocumentSheet = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Add Document or Rate Card")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(AQ.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(AQ.blue.opacity(0.35), lineWidth: 1)
                    )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)

                if engine.profile.documents.isEmpty {
                    NoDocumentsPlaceholder()
                        .padding(.horizontal, 24)
                } else {
                    VStack(spacing: 10) {
                        ForEach(engine.profile.documents) { doc in
                            DocumentRow(doc: doc) {
                                engine.removeDocument(id: doc.id)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                }

                Color.clear.frame(height: 40)
            }
        }
    }
}

// MARK: - Tab Pill

struct TabPill: View {
    let label: String
    let icon: String
    let active: Bool
    let badge: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: active ? .semibold : .regular))
                Text(label)
                    .font(.system(size: 13, weight: active ? .semibold : .regular))
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(active ? .white : AQ.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(active ? AQ.blue : AQ.rule)
                        .clipShape(Capsule())
                }
            }
            .foregroundColor(active ? AQ.blue : AQ.secondary)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                VStack {
                    Spacer()
                    Rectangle()
                        .fill(active ? AQ.blue : Color.clear)
                        .frame(height: 2)
                }
            )
        }
    }
}

// MARK: - Welcome Banner

struct WelcomeBanner: View {
    @State private var pulse = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Pulsing AI orb
            ZStack {
                Circle()
                    .fill(AQ.blue.opacity(0.08))
                    .frame(width: 44, height: 44)
                    .scaleEffect(pulse ? 1.18 : 1.0)
                    .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: pulse)
                Circle()
                    .fill(AQ.blue.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AQ.blue)
            }
            .onAppear { pulse = true }

            VStack(alignment: .leading, spacing: 5) {
                Text("Your rates. Not averages.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AQ.ink)
                Text("Every answer locks in your actual day rate, markup, and terms. Quotes land closer to your real price — every time.")
                    .font(AQ.body(13))
                    .foregroundColor(AQ.secondary)
                    .lineSpacing(4)
            }
        }
        .padding(16)
        .background(AQ.blue.opacity(0.04))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AQ.blue.opacity(0.12), lineWidth: 1)
        )
    }
}

// MARK: - Caught Up Card

struct CaughtUpCard: View {
    let onAddDocument: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(AQ.green)
            Text("Caught up for now")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(AQ.ink)
            Text("More questions will appear automatically as your AI builds a clearer picture of how you price work.")
                .font(AQ.body(14))
                .foregroundColor(AQ.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            Button(action: onAddDocument) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 13, weight: .medium))
                    Text("Upload a rate card or price list")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(AQ.blue)
                .padding(.top, 4)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AQ.rule, lineWidth: 1)
        )
    }
}

// MARK: - Answered Review Section

struct AnsweredReviewSection: View {
    let questions: [OnboardingQuestion]
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { expanded.toggle() }
            } label: {
                HStack {
                    Text("Answered (\(questions.count))")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AQ.secondary)
                        .kerning(0.5)
                        .textCase(.uppercase)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AQ.secondary)
                }
                .padding(.vertical, 12)
            }

            if expanded {
                VStack(spacing: 0) {
                    ForEach(questions) { q in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(q.text)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AQ.label)
                            Text(q.answer)
                                .font(AQ.body(13))
                                .foregroundColor(AQ.secondary)
                        }
                        .padding(.vertical, 12)
                        if q.id != questions.last?.id {
                            Divider().background(AQ.rule)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Documents explainer

struct DocumentsExplainerBanner: View {
    @State private var pulse = false
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(AQ.blue.opacity(0.08))
                    .frame(width: 44, height: 44)
                    .scaleEffect(pulse ? 1.18 : 1.0)
                    .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: pulse)
                Circle()
                    .fill(AQ.blue.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AQ.blue)
            }
            .onAppear { pulse = true }

            VStack(alignment: .leading, spacing: 6) {
                Text("Your numbers, not estimates.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AQ.ink)
                Text("Upload supplier invoices, rate cards, or price lists. The AI reads them directly and quotes using your actual costs — making every quote significantly more accurate.")
                    .font(AQ.body(13))
                    .foregroundColor(AQ.secondary)
                    .lineSpacing(4)
                HStack(spacing: 10) {
                    DocTypeChip(label: "Rate cards", icon: "list.bullet")
                    DocTypeChip(label: "Invoices", icon: "doc.text")
                    DocTypeChip(label: "Certificates", icon: "rosette")
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .background(AQ.blue.opacity(0.04))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AQ.blue.opacity(0.12), lineWidth: 1)
        )
    }
}

struct DocTypeChip: View {
    let label: String; let icon: String
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10))
            Text(label).font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(AQ.blue)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(AQ.blue.opacity(0.08))
        .cornerRadius(6)
    }
}

// MARK: - No Documents Placeholder

struct NoDocumentsPlaceholder: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(AQ.rule)
            Text("No documents yet")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AQ.secondary)
            Text("Price lists and invoices make quotes significantly more accurate.")
                .font(AQ.body(13))
                .foregroundColor(AQ.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}

// MARK: - Document Row

struct DocumentRow: View {
    let doc: ProfileDocument
    let onDelete: () -> Void
    @State private var confirmDelete = false

    var categoryIcon: String {
        switch doc.category {
        case "rate_card":         return "list.bullet.clipboard"
        case "supplier_invoice":  return "doc.text"
        case "certificate":       return "rosette"
        case "template":          return "doc.on.doc"
        default:                  return "paperclip"
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(AQ.blue.opacity(0.08))
                    .frame(width: 40, height: 40)
                Image(systemName: categoryIcon)
                    .font(.system(size: 16, weight: .light))
                    .foregroundColor(AQ.blue)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(doc.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AQ.ink)
                Text(doc.category.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(AQ.body(12))
                    .foregroundColor(AQ.secondary)
            }
            Spacer()
            Button {
                confirmDelete = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundColor(AQ.secondary.opacity(0.5))
            }
            .confirmationDialog("Remove \(doc.name)?", isPresented: $confirmDelete) {
                Button("Remove", role: .destructive) { onDelete() }
                Button("Cancel", role: .cancel) {}
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AQ.rule, lineWidth: 1)
        )
    }
}

// MARK: - Add Document Sheet

struct AddDocumentSheet: View {
    let engine: QuestionEngine
    @Environment(\.dismiss) var dismiss

    @State private var name = ""
    @State private var category = "rate_card"
    @State private var text = ""
    @FocusState private var textFocused: Bool

    let categories = [
        ("rate_card",        "Rate card / price list"),
        ("supplier_invoice", "Supplier invoice"),
        ("certificate",      "Qualification / certificate"),
        ("template",         "Quote template"),
        ("other",            "Other"),
    ]

    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // Explainer
                    Text("Paste the content of a price list, invoice, or rate card. The AI will read it and use the exact figures when quoting.")
                        .font(AQ.body(14))
                        .foregroundColor(AQ.secondary)
                        .lineSpacing(4)
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                        .padding(.bottom, 24)

                    // Document name
                    FieldLabel("Document name")
                    TextField("e.g. Supplier price list — May 2025", text: $name)
                        .font(.system(size: 16))
                        .padding(.horizontal, 16).padding(.vertical, 14)
                        .background(AQ.fill).cornerRadius(12)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)

                    // Category picker
                    FieldLabel("Category")
                    VStack(spacing: 0) {
                        ForEach(categories, id: \.0) { cat in
                            Button {
                                withAnimation(.easeInOut(duration: 0.12)) { category = cat.0 }
                            } label: {
                                HStack {
                                    Text(cat.1)
                                        .font(.system(size: 15))
                                        .foregroundColor(AQ.ink)
                                    Spacer()
                                    if category == cat.0 {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(AQ.blue)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                            }
                            if cat.0 != categories.last?.0 {
                                Divider().background(AQ.rule).padding(.leading, 16)
                            }
                        }
                    }
                    .background(AQ.fill)
                    .cornerRadius(12)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)

                    // Content input
                    FieldLabel("Content")
                    Text("Paste or type the document content. Include prices, rates, and any specifics.")
                        .font(AQ.body(12))
                        .foregroundColor(AQ.secondary)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)
                    TextEditor(text: $text)
                        .font(.system(size: 15))
                        .focused($textFocused)
                        .frame(minHeight: 160)
                        .padding(12)
                        .background(AQ.fill)
                        .cornerRadius(12)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)
                }
            }
            .background(Color.white)
            .navigationTitle("Add Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(AQ.secondary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        let doc = ProfileDocument(
                            id: UUID().uuidString,
                            name: name.trimmingCharacters(in: .whitespaces),
                            category: category,
                            extractedText: text.trimmingCharacters(in: .whitespaces),
                            uploadedAt: Date()
                        )
                        engine.addDocument(doc)
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(canSave ? AQ.blue : AQ.secondary)
                    .disabled(!canSave)
                }
            }
        }
        .onTapGesture { textFocused = false }
    }
}

struct FieldLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .kerning(0.8)
            .foregroundColor(AQ.secondary)
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
    }
}

// MARK: - Question Card

struct QuestionCard: View {
    let question: OnboardingQuestion
    @Binding var inputText: String
    var inputFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    let onSkip: () -> Void

    var categoryColor: Color {
        switch question.category {
        case "pricing":   return AQ.green
        case "workflow":  return Color(red: 0.55, green: 0.36, blue: 0.97)
        case "customers": return Color(red: 0.98, green: 0.62, blue: 0.13)
        case "materials": return Color(red: 0.94, green: 0.27, blue: 0.27)
        default:          return AQ.blue
        }
    }
    var categoryLabel: String {
        switch question.category {
        case "foundation": return "About You"
        case "pricing":    return "Pricing"
        case "workflow":   return "How You Work"
        case "customers":  return "Your Customers"
        case "materials":  return "Materials"
        default:           return question.category.capitalized
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Category tag
            Text(categoryLabel.uppercased())
                .font(.system(size: 10, weight: .bold))
                .kerning(1.4)
                .foregroundColor(categoryColor)
                .padding(.bottom, 12)

            // Question
            Text(question.text)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(AQ.ink)
                .lineSpacing(4)
                .padding(.bottom, 8)

            // Quote impact label
            if !question.quoteImpact.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 11))
                        .foregroundColor(AQ.green)
                    Text(question.quoteImpact)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AQ.green)
                        .lineSpacing(3)
                }
                .padding(.bottom, 20)
            } else {
                Color.clear.frame(height: 20)
            }

            // Input
            TextField(question.hint, text: $inputText, axis: .vertical)
                .font(.system(size: 16))
                .lineLimit(4)
                .focused(inputFocused)
                .submitLabel(.done)
                .onSubmit(onSubmit)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(AQ.fill)
                .cornerRadius(12)
                .padding(.bottom, 20)

            // Buttons
            HStack(spacing: 10) {
                Button(action: onSkip) {
                    Text("Skip")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(AQ.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(AQ.fill)
                        .cornerRadius(12)
                }
                Button(action: onSubmit) {
                    HStack(spacing: 6) {
                        Text("Save")
                            .font(.system(size: 15, weight: .semibold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(inputText.trimmingCharacters(in: .whitespaces).isEmpty
                                     ? AQ.secondary : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(inputText.trimmingCharacters(in: .whitespaces).isEmpty
                                ? AQ.fill : AQ.blue)
                    .cornerRadius(12)
                    .animation(.easeInOut(duration: 0.15), value: inputText.isEmpty)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

