import Foundation
import Combine

// MARK: - Question model

struct OnboardingQuestion: Identifiable, Codable {
    let id: String
    let text: String
    let hint: String          // placeholder / example answer
    let category: String      // "foundation" | "pricing" | "workflow" | "customers" | "materials"
    var answer: String = ""
    var isAnswered: Bool { !answer.trimmingCharacters(in: .whitespaces).isEmpty }
}

// MARK: - Tradesman profile

/// Persisted profile built up during onboarding and ongoing use.
/// Injected into every Claude quote prompt as rich context.
struct TradesmanProfile: Codable {
    var answers: [OnboardingQuestion] = []
    var completedAt: Date?

    // Convenience accessors used when building the Claude system prompt
    var trade: String {
        answers.first(where: { $0.id == "trade" })?.answer ?? ""
    }
    var region: String {
        answers.first(where: { $0.id == "region" })?.answer ?? ""
    }

    /// Generates a rich system-prompt preamble from all answered questions.
    func claudeContext() -> String {
        let answered = answers.filter { $0.isAnswered }
        guard !answered.isEmpty else { return "" }

        var lines = ["## About this tradesperson\n"]
        let grouped = Dictionary(grouping: answered, by: { $0.category })
        let order = ["foundation", "pricing", "workflow", "customers", "materials"]
        for cat in order {
            guard let qs = grouped[cat], !qs.isEmpty else { continue }
            let heading: String
            switch cat {
            case "foundation":  heading = "### Background"
            case "pricing":     heading = "### Pricing & rates"
            case "workflow":    heading = "### How they work"
            case "customers":   heading = "### Their customers"
            case "materials":   heading = "### Materials & suppliers"
            default:            heading = "### \(cat.capitalized)"
            }
            lines.append(heading)
            for q in qs {
                lines.append("**\(q.text)** \(q.answer)")
            }
            lines.append("")
        }
        lines.append("""
        Use this context to personalise every quote — match their typical \
        day rates, material preferences, labour split, and customer \
        expectations. Do not ask questions already answered above.
        """)
        return lines.joined(separator: "\n")
    }
}

// MARK: - Foundation questions (always shown first, in order)

let foundationQuestions: [OnboardingQuestion] = [
    OnboardingQuestion(
        id: "trade",
        text: "What is your trade?",
        hint: "e.g. Electrician, Plumber, Painter & Decorator, Builder…",
        category: "foundation"
    ),
    OnboardingQuestion(
        id: "region",
        text: "Where are you based?",
        hint: "e.g. Manchester, London, Glasgow, Texas, New York…",
        category: "foundation"
    ),
    OnboardingQuestion(
        id: "experience",
        text: "How many years have you been trading?",
        hint: "e.g. 3 years, 15 years…",
        category: "foundation"
    ),
    OnboardingQuestion(
        id: "team_size",
        text: "Do you work alone or do you have a team?",
        hint: "e.g. Solo, 2-person team, 5 employees…",
        category: "foundation"
    ),
    OnboardingQuestion(
        id: "day_rate",
        text: "What is your typical day rate or hourly rate?",
        hint: "e.g. £250/day, £35/hour, $45/hour…",
        category: "pricing"
    ),
    OnboardingQuestion(
        id: "job_size",
        text: "What size jobs do you typically take on?",
        hint: "e.g. Small domestic, large commercial, mix of both…",
        category: "foundation"
    ),
]

// MARK: - Question Engine

/// Drives the onboarding flywheel. Manages question sequencing,
/// calls Claude to generate follow-up questions based on answers so far,
/// and persists the profile to UserDefaults.
@MainActor
final class QuestionEngine: ObservableObject {

    static let shared = QuestionEngine()

    @Published var questions: [OnboardingQuestion] = []
    @Published var currentIndex: Int = 0
    @Published var isGeneratingMore: Bool = false
    @Published var profile: TradesmanProfile = TradesmanProfile()

    private static let profileKey = "aq_tradesman_profile"
    private static let claudeEndpoint = "\(WEB_APP_BASE_URL)/api/claude"

    private var generationTask: Task<Void, Never>?
    private var hasGeneratedFollowUps = false

    private init() {
        loadProfile()
        if questions.isEmpty {
            questions = foundationQuestions
        }
    }

    // MARK: - Current question

    var currentQuestion: OnboardingQuestion? {
        guard currentIndex < questions.count else { return nil }
        return questions[currentIndex]
    }

    var progress: Double {
        guard !questions.isEmpty else { return 0 }
        let answered = questions.filter { $0.isAnswered }.count
        return Double(answered) / Double(max(questions.count, 10))
    }

    var answeredCount: Int { questions.filter { $0.isAnswered }.count }

    // MARK: - Answer submission

    func submitAnswer(_ answer: String) {
        guard currentIndex < questions.count else { return }
        questions[currentIndex].answer = answer.trimmingCharacters(in: .whitespaces)
        profile.answers = questions

        // After foundation questions are done, generate follow-ups
        let foundationDone = foundationQuestions.allSatisfy { fq in
            questions.first(where: { $0.id == fq.id })?.isAnswered == true
        }
        if foundationDone && !hasGeneratedFollowUps {
            hasGeneratedFollowUps = true
            generateFollowUpQuestions()
        }

        // Advance to next unanswered question
        advanceToNext()
        saveProfile()
    }

    func skipCurrent() {
        advanceToNext()
    }

    private func advanceToNext() {
        // Find next unanswered question after current
        let next = ((currentIndex + 1)..<questions.count).first { !questions[$0].isAnswered }
        if let next {
            currentIndex = next
        } else {
            // All answered — generate more if we have a trade set
            currentIndex = questions.count  // signals "all done for now"
            if !profile.trade.isEmpty && !isGeneratingMore {
                generateFollowUpQuestions()
            }
        }
    }

    // MARK: - Claude-generated follow-up questions

    private func generateFollowUpQuestions() {
        guard !profile.trade.isEmpty else { return }
        isGeneratingMore = true

        generationTask = Task {
            let newQuestions = await fetchFollowUpQuestions()
            // Append only questions not already in the list
            let existingIDs = Set(questions.map { $0.id })
            let fresh = newQuestions.filter { !existingIDs.contains($0.id) }
            questions.append(contentsOf: fresh)
            // If we were at the end, advance to the first new question
            if currentIndex >= questions.count - fresh.count {
                currentIndex = questions.count - fresh.count
            }
            isGeneratingMore = false
            saveProfile()
        }
    }

    private func fetchFollowUpQuestions() async -> [OnboardingQuestion] {
        let answeredSummary = questions
            .filter { $0.isAnswered }
            .map { "Q: \($0.text)\nA: \($0.answer)" }
            .joined(separator: "\n\n")

        let prompt = """
        You are building a personalised AI quoting assistant for a tradesperson.
        Based on their answers so far, generate exactly 8 highly specific follow-up \
        questions that will help you produce more accurate quotes for them.

        Their answers so far:
        \(answeredSummary)

        Rules:
        - Questions must be specific to their trade (\(profile.trade)) and region (\(profile.region))
        - Cover: materials they prefer, markup %, VAT status, typical job duration, \
          payment terms, labour-to-materials ratio, what they include/exclude in quotes, \
          any specialist skills or certifications
        - Do NOT repeat questions already answered above
        - Each question needs a short example hint

        Respond with ONLY valid JSON, no markdown, no explanation:
        [
          {
            "id": "unique_snake_case_id",
            "text": "Question text?",
            "hint": "e.g. example answer",
            "category": "pricing|workflow|customers|materials"
          }
        ]
        """

        guard let url = URL(string: Self.claudeEndpoint) else { return [] }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",  // fast + cheap for question gen
            "max_tokens": 1024,
            "messages": [["role": "user", "content": prompt]]
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return [] }
        request.httpBody = bodyData

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            // Parse Claude response
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let content = json["content"] as? [[String: Any]],
               let text = content.first?["text"] as? String {
                // Extract JSON array from the response text
                if let jsonStart = text.firstIndex(of: "["),
                   let jsonEnd = text.lastIndex(of: "]") {
                    let jsonSlice = String(text[jsonStart...jsonEnd])
                    if let jsonData = jsonSlice.data(using: .utf8),
                       let raw = try? JSONDecoder().decode([[String: String]].self,
                                                           from: jsonData) {
                        return raw.compactMap { dict in
                            guard let id   = dict["id"],
                                  let text = dict["text"],
                                  let hint = dict["hint"],
                                  let cat  = dict["category"] else { return nil }
                            return OnboardingQuestion(id: id, text: text,
                                                      hint: hint, category: cat)
                        }
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
        // Merge saved answers back into question list
        var merged = foundationQuestions
        for i in merged.indices {
            if let saved = saved.answers.first(where: { $0.id == merged[i].id }) {
                merged[i].answer = saved.answer
            }
        }
        // Re-append any generated follow-up questions that were saved
        let foundationIDs = Set(foundationQuestions.map { $0.id })
        let followUps = saved.answers.filter { !foundationIDs.contains($0.id) }
        merged.append(contentsOf: followUps)
        questions = merged
        hasGeneratedFollowUps = !followUps.isEmpty

        // Start at first unanswered question
        currentIndex = questions.firstIndex(where: { !$0.isAnswered }) ?? questions.count
    }

    /// Export profile context for injection into quote prompts
    func claudeContext() -> String {
        profile.claudeContext()
    }
}
