import SwiftUI
import RoomPlan
import ARKit
import SceneKit

// MARK: - Design tokens

private enum AQ {
    // Palette
    static let ink       = Color(red: 0.07, green: 0.07, blue: 0.09)      // near-black
    static let label     = Color(red: 0.18, green: 0.18, blue: 0.22)
    static let secondary = Color(red: 0.52, green: 0.52, blue: 0.56)
    static let rule      = Color(red: 0.88, green: 0.88, blue: 0.91)
    static let fill      = Color(red: 0.96, green: 0.96, blue: 0.97)
    static let blue      = Color(red: 0.00, green: 0.48, blue: 1.00)      // iOS system blue
    static let green     = Color(red: 0.13, green: 0.72, blue: 0.43)
    static let amber     = Color(red: 1.00, green: 0.80, blue: 0.00)

    // Type
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }
    static func title(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .default)
    }
    static func body(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }
    static func caption(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .default)
    }
    static func mono(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
}

// MARK: - Ready View

struct ReadyView: View {
    @ObservedObject var coordinator: ScanCoordinator
    @EnvironmentObject var questionEngine: QuestionEngine
    @State private var showOnboarding = false
    @State private var pulseIcon = false

    var body: some View {
        VStack(spacing: 0) {

            // ── Navigation bar ──────────────────────────────────────────────
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AccuQuote")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(AQ.ink)
                    Text("Room Scanner")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(AQ.secondary)
                }
                Spacer()
                AIProfileButton(
                    answered: questionEngine.answeredCount,
                    pct: questionEngine.personalisation
                ) { showOnboarding = true }
            }
            .padding(.horizontal, 24)
            .padding(.top, 56)
            .padding(.bottom, 32)

            Divider().background(AQ.rule).padding(.horizontal, 24)

            // ── Hero ────────────────────────────────────────────────────────
            Spacer()

            ZStack {
                // Outer ring — faint
                Circle()
                    .stroke(AQ.blue.opacity(0.08), lineWidth: 1)
                    .frame(width: 160, height: 160)
                // Mid ring — subtle
                Circle()
                    .stroke(AQ.blue.opacity(0.14), lineWidth: 1)
                    .frame(width: 120, height: 120)
                // Core
                Circle()
                    .fill(AQ.fill)
                    .frame(width: 80, height: 80)
                Image(systemName: scanIcon)
                    .font(.system(size: 30, weight: .light))
                    .foregroundColor(AQ.blue)
                    .scaleEffect(pulseIcon ? 1.06 : 1.0)
                    .animation(
                        .easeInOut(duration: 2.4).repeatForever(autoreverses: true),
                        value: pulseIcon
                    )
            }
            .onAppear { pulseIcon = true }
            .padding(.bottom, 36)

            // Headline
            Text("Scan the Room")
                .font(.system(size: 38, weight: .bold))
                .foregroundColor(AQ.ink)
                .padding(.bottom, 10)

            // Method badge
            ScanMethodBadge(method: coordinator.scanMethod)
                .padding(.bottom, 20)

            // Description
            Text(coordinator.scanMethod.description)
                .font(AQ.body(15))
                .foregroundColor(AQ.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .padding(.horizontal, 44)

            // Instructions
            if coordinator.scanMethod != .lidar {
                ScanInstructionList(method: coordinator.scanMethod)
                    .padding(.top, 28)
                    .padding(.horizontal, 44)
            }

            Spacer()

            // ── CTA ─────────────────────────────────────────────────────────
            VStack(spacing: 0) {
                Divider().background(AQ.rule)
                    .padding(.bottom, 20)

                Button { coordinator.startScan() } label: {
                    Text("Start Scan")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(AQ.blue)
                        .cornerRadius(14)
                }
                .padding(.horizontal, 24)

                Text(deviceRequirementText)
                    .font(AQ.body(12))
                    .foregroundColor(AQ.secondary.opacity(0.7))
                    .padding(.top, 12)
                    .padding(.bottom, 36)
            }
        }
        .background(Color.white)
        .sheet(isPresented: $showOnboarding) {
            OnboardingSheet().environmentObject(questionEngine)
        }
    }

    var scanIcon: String {
        switch coordinator.scanMethod {
        case .lidar:      return "cube.transparent"
        case .sceneDepth: return "sensor.tag.radiowaves.forward"
        case .arPlanes:   return "camera"
        }
    }

    var deviceRequirementText: String {
        switch coordinator.scanMethod {
        case .lidar:      return "LiDAR · iPhone 12 Pro or later"
        case .sceneDepth: return "Depth sensor · Face ID iPhone XS or later"
        case .arPlanes:   return "Camera · any ARKit device"
        }
    }
}

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
                    Text("\(pct)% accurate")
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
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(answered > 0 ? AQ.green.opacity(0.3) : AQ.blue.opacity(0.3), lineWidth: 1)
            )
        }
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

            Text(pct > 0 ? "\(pct)% quote accuracy" : "Not set up")
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
        case .sceneDepth: return AQ.blue
        case .arPlanes:   return AQ.secondary
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

// MARK: - Scan Instruction List

struct ScanInstructionList: View {
    let method: ScanMethod
    var steps: [(String, String)] {
        switch method {
        case .sceneDepth: return [
            ("Walk slowly around the room", "arrow.triangle.2.circlepath"),
            ("Point at each wall for 1–2 seconds", "sensor.tag.radiowaves.forward"),
            ("Include ceiling and floor", "arrow.up.arrow.down"),
        ]
        case .arPlanes: return [
            ("Point camera slowly at each wall", "camera.metering.spot"),
            ("Hold steady for 2–3 seconds per wall", "hand.raised"),
            ("Cover all four walls", "square.on.square"),
        ]
        default: return []
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(steps.enumerated()), id: \.offset) { idx, step in
                HStack(alignment: .top, spacing: 14) {
                    Text("\(idx + 1)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AQ.blue)
                        .frame(width: 22, height: 22)
                        .background(AQ.blue.opacity(0.08))
                        .clipShape(Circle())
                    Text(step.0)
                        .font(AQ.body(14))
                        .foregroundColor(AQ.label)
                        .lineSpacing(3)
                }
            }
        }
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
        NavigationView {
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
                        if engine.isGeneratingMore {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.5)
                                    .tint(AQ.blue)
                                Text("learning…")
                                    .font(.system(size: 11))
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

            VStack(alignment: .leading, spacing: 6) {
                Text("The more you share, the more accurate every quote.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AQ.ink)
                    .lineSpacing(3)
                Text("Answer each question so the AI knows your exact rates, materials, and how you price jobs. Tradesmen who complete this earn back their subscription in their first quote.")
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
        NavigationView {
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

private struct FieldLabel: View {
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


// MARK: - Scanning View

struct ScanningView: View {
    @ObservedObject var coordinator: ScanCoordinator
    var body: some View {
        switch coordinator.scanMethod {
        case .lidar:      LiDARScanningView(coordinator: coordinator)
        case .sceneDepth: DepthScanningView(coordinator: coordinator)
        case .arPlanes:   DepthScanningView(coordinator: coordinator)
        }
    }
}

// MARK: - LiDAR Scanning View

struct LiDARScanningView: View {
    @ObservedObject var coordinator: ScanCoordinator
    var body: some View {
        ZStack(alignment: .bottom) {
            if let captureView = coordinator.captureView {
                RoomCaptureViewRepresentable(captureView: captureView).ignoresSafeArea()
            }
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button { coordinator.stopScan() } label: {
                        Text("Done")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial)
                            .cornerRadius(22)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                Spacer()
                ScanHUD(coordinator: coordinator)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 44)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Depth Scanning View

struct DepthScanningView: View {
    @ObservedObject var coordinator: ScanCoordinator
    var minFrames: Int { coordinator.scanMethod == .sceneDepth ? 8 : 3 }

    var body: some View {
        ZStack(alignment: .bottom) {
            if let session = coordinator.arSession {
                ARViewRepresentable(session: session).ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    // Frame counter
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.white.opacity(0.9))
                            .frame(width: 6, height: 6)
                        Text(coordinator.scanMethod == .sceneDepth
                             ? "\(coordinator.frameCount) frames"
                             : "\(coordinator.frameCount) walls")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(22)

                    Spacer()

                    Button { coordinator.stopScan() } label: {
                        Text("Done")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(coordinator.frameCount >= minFrames ? AQ.ink : .white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(coordinator.frameCount >= minFrames
                                        ? Color.white : Color.white.opacity(0.15))
                            .cornerRadius(22)
                            .animation(.easeInOut(duration: 0.2), value: coordinator.frameCount >= minFrames)
                    }
                    .disabled(coordinator.frameCount < minFrames)
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)

                Spacer()

                // Progress ring
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 2)
                        .frame(width: 140, height: 140)
                    Circle()
                        .trim(from: 0, to: CGFloat(coordinator.scanProgress))
                        .stroke(Color.white,
                                style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 140, height: 140)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.3), value: coordinator.scanProgress)
                    VStack(spacing: 2) {
                        Text("\(Int(coordinator.scanProgress * 100))%")
                            .font(.system(size: 32, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                        Text("scanned")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding(.bottom, 24)

                ScanHUD(coordinator: coordinator)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 44)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Scan HUD (shared bottom card)

struct ScanHUD: View {
    @ObservedObject var coordinator: ScanCoordinator
    var body: some View {
        VStack(spacing: 10) {
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15))
                    Capsule()
                        .fill(Color.white)
                        .frame(width: geo.size.width * CGFloat(coordinator.scanProgress))
                        .animation(.easeInOut(duration: 0.4), value: coordinator.scanProgress)
                }
            }
            .frame(height: 3)
            Text(coordinator.instructionText)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.black.opacity(0.55))
                .background(.ultraThinMaterial)
                .cornerRadius(18)
        )
    }
}

// MARK: - Processing View

struct ProcessingView: View {
    @State private var rotation = 0.0
    @State private var dotPhase = 0

    var body: some View {
        VStack(spacing: 0) {

            Spacer()

            // Spinner
            ZStack {
                Circle()
                    .stroke(AQ.rule, lineWidth: 1.5)
                    .frame(width: 64, height: 64)
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(AQ.blue, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: 64, height: 64)
                    .rotationEffect(.degrees(rotation))
                    .onAppear {
                        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                            rotation = 360
                        }
                    }
            }
            .padding(.bottom, 32)

            Text("Processing Scan")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(AQ.ink)
                .padding(.bottom, 8)
            Text("Calculating dimensions…")
                .font(AQ.body(15))
                .foregroundColor(AQ.secondary)

            Spacer()
        }
        .background(Color.white)
    }
}

// MARK: - Result View

struct ResultView: View {
    let result: RoomDimensions
    @ObservedObject var coordinator: ScanCoordinator
    @State private var sent = false

    var body: some View {
        VStack(spacing: 0) {

            // Header
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AccuQuote")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(AQ.ink)
                    Text("Scan complete")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(AQ.green)
                }
                Spacer()
                ZStack {
                    Circle().fill(AQ.green.opacity(0.1)).frame(width: 36, height: 36)
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AQ.green)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 56)
            .padding(.bottom, 28)

            Divider().background(AQ.rule).padding(.horizontal, 24).padding(.bottom, 28)

            // Dimensions card
            VStack(spacing: 0) {

                // Card header
                HStack {
                    Text("Room Dimensions")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AQ.secondary)
                        .kerning(0.8)
                        .textCase(.uppercase)
                    Spacer()
                    HStack(spacing: 6) {
                        Text(result.roomType.capitalized)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AQ.secondary)
                        Text("·")
                            .foregroundColor(AQ.rule)
                        Text(result.scanMethod.accuracyLabel)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(hex: result.scanMethod.accuracyHex))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 20)

                Divider().background(AQ.rule).padding(.horizontal, 20)

                // L / W / H
                HStack(spacing: 0) {
                    DimensionCell(label: "Length", value: result.lengthStr, unit: "m")
                    Divider().frame(height: 60).background(AQ.rule)
                    DimensionCell(label: "Width",  value: result.widthStr,  unit: "m")
                    Divider().frame(height: 60).background(AQ.rule)
                    DimensionCell(label: "Height", value: result.heightStr, unit: "m")
                }
                .padding(.vertical, 4)

                Divider().background(AQ.rule).padding(.horizontal, 20)

                // Stats row
                HStack(spacing: 0) {
                    StatCell(label: "Floor area", value: String(format: "%.1f m²", result.floorArea))
                    Divider().frame(height: 44).background(AQ.rule)
                    StatCell(label: "Doors",      value: "\(result.doorCount)")
                    Divider().frame(height: 44).background(AQ.rule)
                    StatCell(label: "Windows",    value: "\(result.windowCount)")
                }
                .padding(.vertical, 4)
                .padding(.bottom, 8)
            }
            .background(Color.white)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(AQ.rule, lineWidth: 1)
            )
            .padding(.horizontal, 24)

            Spacer()

            // CTA
            VStack(spacing: 0) {
                Divider().background(AQ.rule).padding(.bottom, 20)

                Button {
                    coordinator.sendResultToAccuQuote(result: result)
                    withAnimation(.easeInOut(duration: 0.2)) { sent = true }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: sent ? "checkmark" : "arrow.right.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text(sent ? "Sent to AccuQuote" : "Send to AccuQuote")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(sent ? AQ.green : AQ.blue)
                    .cornerRadius(14)
                }
                .padding(.horizontal, 24)
                .disabled(sent)

                Button { coordinator.reset() } label: {
                    Text("Scan Again")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(AQ.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .background(AQ.fill)
    }
}

// MARK: - Error View

struct ErrorView: View {
    let message: String
    @ObservedObject var coordinator: ScanCoordinator
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color(red: 0.98, green: 0.96, blue: 0.94))
                    .frame(width: 80, height: 80)
                Image(systemName: "exclamationmark")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundColor(Color(red: 0.85, green: 0.40, blue: 0.20))
            }
            .padding(.bottom, 28)

            Text("Scan Failed")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(AQ.ink)
                .padding(.bottom, 10)
            Text(message)
                .font(AQ.body(15))
                .foregroundColor(AQ.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 40)

            Spacer()

            VStack(spacing: 0) {
                Divider().background(AQ.rule).padding(.bottom, 20)
                Button { coordinator.reset() } label: {
                    Text("Try Again")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(AQ.blue)
                        .cornerRadius(14)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 44)
            }
        }
        .background(Color.white)
    }
}

// MARK: - Result sub-components

struct DimensionCell: View {
    let label: String; let value: String; let unit: String
    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(AQ.secondary)
                .kerning(0.5)
                .textCase(.uppercase)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundColor(AQ.ink)
                Text(unit)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(AQ.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}

struct StatCell: View {
    let label: String; let value: String
    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AQ.ink)
            Text(label)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(AQ.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }
}

// MARK: - UIViewRepresentable wrappers

struct RoomCaptureViewRepresentable: UIViewRepresentable {
    let captureView: RoomCaptureView
    func makeUIView(context: Context) -> RoomCaptureView { captureView }
    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}
}

struct ARViewRepresentable: UIViewRepresentable {
    let session: ARSession
    func makeUIView(context: Context) -> ARSCNView {
        let v = ARSCNView()
        v.session = session
        v.automaticallyUpdatesLighting = true
        return v
    }
    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}

// MARK: - Color extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
