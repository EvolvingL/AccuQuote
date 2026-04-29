import Foundation
import Combine

// MARK: - Question model

struct OnboardingQuestion: Identifiable, Codable {
    let id: String
    let text: String
    let hint: String
    let category: String    // "foundation" | "pricing" | "labour" | "materials" | "markup" | "scope" | "admin" | "customers"
    let quoteImpact: String // short reason WHY this improves quote accuracy — shown as sub-label in UI
    var answer: String = ""
    var isAnswered: Bool { !answer.trimmingCharacters(in: .whitespaces).isEmpty }
}

// MARK: - Uploaded document

struct ProfileDocument: Identifiable, Codable {
    let id: String
    let name: String            // display name e.g. "Supplier price list — May 2025"
    let category: String        // "rate_card" | "supplier_invoice" | "certificate" | "template" | "other"
    let extractedText: String   // OCR / user-typed summary injected into Claude context
    let uploadedAt: Date
}

// MARK: - Tradesman profile

struct TradesmanProfile: Codable {
    var answers: [OnboardingQuestion] = []
    var documents: [ProfileDocument] = []
    var completedAt: Date?

    var trade: String  { answers.first(where: { $0.id == "trade"  })?.answer ?? "" }
    var region: String { answers.first(where: { $0.id == "region" })?.answer ?? "" }

    /// Full system-prompt preamble injected before every quote request.
    func claudeContext() -> String {
        var sections: [String] = []

        // ── Answers ──────────────────────────────────────────────────────────
        let answered = answers.filter { $0.isAnswered }
        if !answered.isEmpty {
            sections.append("## Tradesperson profile\n")
            let order = ["foundation", "pricing", "labour", "materials", "markup", "scope", "admin", "customers"]
            let grouped = Dictionary(grouping: answered, by: { $0.category })
            let headings: [String: String] = [
                "foundation": "### Background",
                "pricing":    "### Day rates & pricing",
                "labour":     "### Labour & team",
                "materials":  "### Materials & suppliers",
                "markup":     "### Markup & margins",
                "scope":      "### What's included in quotes",
                "admin":      "### Admin & payment terms",
                "customers":  "### Customer types",
            ]
            for cat in order {
                guard let qs = grouped[cat], !qs.isEmpty else { continue }
                sections.append(headings[cat] ?? "### \(cat.capitalized)")
                for q in qs {
                    sections.append("- **\(q.text)** \(q.answer)")
                }
                sections.append("")
            }
        }

        // ── Documents ────────────────────────────────────────────────────────
        if !documents.isEmpty {
            sections.append("## Uploaded business documents\n")
            for doc in documents {
                sections.append("### \(doc.name) [\(doc.category)]")
                sections.append(doc.extractedText)
                sections.append("")
            }
        }

        guard !sections.isEmpty else { return "" }

        sections.append("""
        ## Quoting instructions
        Use ALL of the above context to produce quotes. Specifically:
        - Use this tradesperson's actual day rates, not industry averages
        - Apply their stated material markup and labour split
        - Include only what they say they normally include in a quote
        - Match their payment terms and VAT status
        - Reference their preferred suppliers and materials where relevant
        - Do NOT ask for information already provided above
        """)

        return sections.joined(separator: "\n")
    }
}

// MARK: - Foundation questions
// Every question here has a direct, explicit impact on quote accuracy.

let foundationQuestions: [OnboardingQuestion] = [
    OnboardingQuestion(
        id: "trade",
        text: "What is your trade?",
        hint: "e.g. Electrician, Plumber, Painter & Decorator, Plasterer, Builder…",
        category: "foundation",
        quoteImpact: "Sets the scope of every quote"
    ),
    OnboardingQuestion(
        id: "region",
        text: "Where are you based?",
        hint: "e.g. Manchester, London, Glasgow, Texas, New York…",
        category: "foundation",
        quoteImpact: "Determines local labour and material rates"
    ),
    OnboardingQuestion(
        id: "day_rate",
        text: "What do you charge per day, or per hour?",
        hint: "e.g. £280/day, £40/hour — include any callout rates if different",
        category: "pricing",
        quoteImpact: "The single biggest variable in every quote"
    ),
    OnboardingQuestion(
        id: "team_size",
        text: "How many people do you typically put on a job?",
        hint: "e.g. Just me, me + 1 labourer, team of 3…",
        category: "labour",
        quoteImpact: "Multiplies your labour cost per day"
    ),
    OnboardingQuestion(
        id: "material_markup",
        text: "What percentage do you mark up materials?",
        hint: "e.g. 15%, 20%, cost price — or do you charge materials at trade?",
        category: "markup",
        quoteImpact: "Directly affects every line item with materials"
    ),
    OnboardingQuestion(
        id: "vat",
        text: "Are you VAT registered?",
        hint: "e.g. Yes — 20% VAT added to all quotes, No — not VAT registered",
        category: "admin",
        quoteImpact: "Changes the total on every quote you send"
    ),
    OnboardingQuestion(
        id: "what_included",
        text: "What do you normally include in a quote — labour only, or labour and materials?",
        hint: "e.g. Labour + materials, labour only (customer buys materials), depends on job…",
        category: "scope",
        quoteImpact: "Defines what the AI prices up by default"
    ),
    OnboardingQuestion(
        id: "waste_disposal",
        text: "Do you include waste removal and skip hire in your quotes?",
        hint: "e.g. Always included, charged separately, customer arranges…",
        category: "scope",
        quoteImpact: "Often £200–£800 per job if missed"
    ),
]

// MARK: - Question Engine

@MainActor
final class QuestionEngine: ObservableObject {

    static let shared = QuestionEngine()

    @Published var questions: [OnboardingQuestion] = []
    @Published var currentIndex: Int = 0
    @Published var isGeneratingMore: Bool = false
    @Published var profile: TradesmanProfile = TradesmanProfile()

    private static let profileKey = "aq_tradesman_profile"

    private var generationTask: Task<Void, Never>?
    private var generationRound = 0     // tracks how many batches we've generated
    private let maxRounds = 10          // effectively unlimited for typical use

    private init() {
        loadProfile()
        if questions.isEmpty {
            questions = foundationQuestions
        }
    }

    // MARK: - Accessors

    var currentQuestion: OnboardingQuestion? {
        guard currentIndex < questions.count else { return nil }
        return questions[currentIndex]
    }

    var progress: Double {
        guard !questions.isEmpty else { return 0 }
        return Double(answeredCount) / Double(max(questions.count, 10))
    }

    var answeredCount: Int { questions.filter { $0.isAnswered }.count }

    /// Personalisation score (0–95).
    /// Foundation questions (8) bring the score to ~75%.
    /// Follow-up questions push it toward 95%.
    /// The unlock threshold is 70%, so completing all foundation questions is sufficient.
    var personalisation: Int {
        let foundationTotal = foundationQuestions.count   // 8
        let foundationAnswered = questions
            .filter { q in foundationQuestions.contains(where: { $0.id == q.id }) && q.isAnswered }
            .count
        let followUpAnswered = max(0, answeredCount - foundationAnswered)

        // Foundation: 0–75% linearly across 8 questions
        let foundationScore = Double(foundationAnswered) / Double(foundationTotal) * 75.0
        // Follow-ups: 75–95% asymptotically (each follow-up worth less)
        let followUpScore = min(Double(followUpAnswered) / 10.0 * 20.0, 20.0)

        return min(Int(foundationScore + followUpScore), 95)
    }

    // MARK: - Answer submission

    func submitAnswer(_ answer: String) {
        guard currentIndex < questions.count else { return }
        questions[currentIndex].answer = answer.trimmingCharacters(in: .whitespaces)
        profile.answers = questions
        advanceToNext()
        saveProfile()
        triggerGenerationIfNeeded()
    }

    func skipCurrent() {
        advanceToNext()
        triggerGenerationIfNeeded()
    }

    // MARK: - Demo / testing

    /// Bulk-loads a realistic demo profile (electrician, Manchester).
    /// Use during testing to bypass the question flow instantly.
    func loadDemoProfile() {
        let demoAnswers: [String: String] = [
            "trade":            "Electrician",
            "region":           "Manchester",
            "day_rate":         "£320/day, £45/hour for callouts",
            "team_size":        "Just me, occasionally me + 1 apprentice on larger jobs",
            "material_markup":  "20% on all materials",
            "vat":              "Yes — VAT registered, 20% added to all quotes",
            "what_included":    "Labour and materials included unless stated otherwise",
            "waste_disposal":   "I include disposal for small jobs; skip hire charged separately on large refurbs",
        ]
        for i in questions.indices {
            if let ans = demoAnswers[questions[i].id] {
                questions[i].answer = ans
            }
        }
        profile.answers = questions
        currentIndex = questions.firstIndex(where: { !$0.isAnswered }) ?? questions.count
        saveProfile()
        triggerGenerationIfNeeded()
    }

    // MARK: - Document upload

    func addDocument(_ doc: ProfileDocument) {
        profile.documents.append(doc)
        saveProfile()
        // Re-generate questions now we have new context
        generateNextBatch()
    }

    func removeDocument(id: String) {
        profile.documents.removeAll { $0.id == id }
        saveProfile()
    }

    // MARK: - Navigation

    private func advanceToNext() {
        let next = ((currentIndex + 1)..<questions.count).first { !questions[$0].isAnswered }
        if let next {
            currentIndex = next
        } else {
            currentIndex = questions.count  // signals "end of current list"
        }
    }

    // Generate after every answer once foundation is done; also generate
    // proactively when the user reaches the end of the list.
    private func triggerGenerationIfNeeded() {
        let foundationDone = foundationQuestions.allSatisfy { fq in
            questions.first(where: { $0.id == fq.id })?.isAnswered == true
        }
        guard foundationDone else { return }

        // Generate immediately after each answer once foundation complete,
        // but throttle: only if fewer than 4 unanswered questions remain.
        let unanswered = questions.filter { !$0.isAnswered }.count
        if unanswered < 4 && !isGeneratingMore && generationRound < maxRounds {
            generateNextBatch()
        }
    }

    // MARK: - Claude question generation

    private func generateNextBatch() {
        guard !profile.trade.isEmpty, !isGeneratingMore else { return }
        isGeneratingMore = true
        generationRound += 1

        generationTask?.cancel()
        generationTask = Task {
            let newQuestions = await fetchQuotingQuestions()
            guard !Task.isCancelled else {
                isGeneratingMore = false
                return
            }
            let existingIDs = Set(questions.map { $0.id })
            let fresh = newQuestions.filter { !existingIDs.contains($0.id) }
            questions.append(contentsOf: fresh)
            if currentIndex >= questions.count - fresh.count {
                currentIndex = questions.count - fresh.count
            }
            isGeneratingMore = false
            saveProfile()
        }
    }

    private func fetchQuotingQuestions() async -> [OnboardingQuestion] {
        let answeredSummary = questions
            .filter { $0.isAnswered }
            .map { "Q: \($0.text)\nA: \($0.answer)" }
            .joined(separator: "\n\n")

        let documentSummary: String
        if profile.documents.isEmpty {
            documentSummary = "None uploaded yet."
        } else {
            documentSummary = profile.documents
                .map { "- \($0.name) (\($0.category))" }
                .joined(separator: "\n")
        }

        let prompt = """
        You are setting up an AI assistant that will produce accurate, ready-to-send \
        quotes for a \(profile.trade) based in \(profile.region).

        Your ONLY goal is to extract the information needed to make quotes accurate. \
        A quote has these components you must fill correctly:
        1. Labour cost (day rate × days × team size)
        2. Materials cost (quantity × unit price × markup)
        3. Waste/disposal
        4. Travel or site costs
        5. Subcontractor costs
        6. Contingency
        7. VAT
        8. Payment terms and deposit

        Answers already collected:
        \(answeredSummary)

        Documents already uploaded:
        \(documentSummary)

        Round \(generationRound) of questioning.

        Generate exactly 6 questions that fill the BIGGEST remaining gaps in quoting accuracy. \
        Prioritise in this order:
        1. Any of the 8 quote components above that are still unknown
        2. Trade-specific costs unique to \(profile.trade) that are commonly missed \
           (e.g. for electricians: testing & certification fees, first-fix vs second-fix rates; \
           for plumbers: pressure testing, commissioning; for painters: coats of paint, prep time)
        3. Job-type variations (e.g. new build vs refurb rates, commercial vs domestic pricing)
        4. Supplier relationships and preferred product specs that affect material costs
        5. Any quirks or non-standard practices they use that would change a quote

        Rules:
        - Every question must have a direct, measurable impact on quote accuracy
        - Do NOT ask vague questions like "tell me about your business"
        - Do NOT repeat any question already answered above
        - Each question must include a concrete hint showing what a real answer looks like
        - The "quoteImpact" field must explain in one sentence exactly how the answer changes a quote number

        Respond with ONLY valid JSON, no markdown:
        [
          {
            "id": "unique_snake_case_id",
            "text": "Specific question?",
            "hint": "e.g. realistic example answer",
            "category": "pricing|labour|materials|markup|scope|admin|customers",
            "quoteImpact": "One sentence: how this answer changes the quote total"
          }
        ]
        """

        guard let url = URL(string: ANTHROPIC_API_URL) else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(ANTHROPIC_API_KEY, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 1500,
            "messages": [["role": "user", "content": prompt]]
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return [] }
        request.httpBody = bodyData

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let content = json["content"] as? [[String: Any]],
               let text = content.first?["text"] as? String,
               let jsonStart = text.firstIndex(of: "["),
               let jsonEnd = text.lastIndex(of: "]") {
                let slice = String(text[jsonStart...jsonEnd])
                if let sliceData = slice.data(using: .utf8),
                   let raw = try? JSONDecoder().decode([[String: String]].self, from: sliceData) {
                    return raw.compactMap { dict in
                        guard let id     = dict["id"],
                              let text   = dict["text"],
                              let hint   = dict["hint"],
                              let cat    = dict["category"],
                              let impact = dict["quoteImpact"] else { return nil }
                        return OnboardingQuestion(id: id, text: text, hint: hint,
                                                  category: cat, quoteImpact: impact)
                    }
                }
            }
        } catch {}
        return []
    }

    // MARK: - Persistence

    private func saveProfile() {
        profile.answers = questions
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: Self.profileKey)
        }
    }

    private func loadProfile() {
        guard let data = UserDefaults.standard.data(forKey: Self.profileKey),
              let saved = try? JSONDecoder().decode(TradesmanProfile.self, from: data)
        else {
            questions = foundationQuestions
            return
        }
        profile = saved

        var merged = foundationQuestions
        for i in merged.indices {
            if let s = saved.answers.first(where: { $0.id == merged[i].id }) {
                merged[i].answer = s.answer
            }
        }
        let foundationIDs = Set(foundationQuestions.map { $0.id })
        let followUps = saved.answers.filter { !foundationIDs.contains($0.id) }
        merged.append(contentsOf: followUps)
        questions = merged
        if !followUps.isEmpty { generationRound = 1 }

        currentIndex = questions.firstIndex(where: { !$0.isAnswered }) ?? questions.count
    }

    func claudeContext() -> String { profile.claudeContext() }
}
