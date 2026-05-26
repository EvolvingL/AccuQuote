import SwiftUI
import RoomPlan
import ARKit
import SceneKit

// MARK: - Design tokens

enum AQ {
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

// MARK: - Logo component
// Displays the AccuQuote horizontal logo on a dark pill so the JPEG renders correctly
// against the app's white background.

struct AQLogoView: View {
    var height: CGFloat = 22
    var body: some View {
        if let uiImage = UIImage(named: "accuquote-logo") {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: height * 0.2))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(red: 0.06, green: 0.07, blue: 0.13))
                .clipShape(RoundedRectangle(cornerRadius: height * 0.3))
        } else {
            Text("AccuQuote")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(AQ.ink)
        }
    }
}

// Threshold for the ProfileGateView unlock indicator (used in OnboardingSheet)
let profileUnlockThreshold = 70

// MARK: - Profile Gate View
// Shown in OnboardingSheet; the unlock banner fires at profileUnlockThreshold (70%).

struct ProfileGateView: View {
    var onGuestTap: (() -> Void)? = nil
    @EnvironmentObject var engine: QuestionEngine
    @State private var inputText = ""
    @FocusState private var inputFocused: Bool
    @State private var showDocumentSheet = false
    @State private var unlockPulse = false
    @State private var ringProgress: CGFloat = 0

    private var pct: Int { engine.personalisation }
    private var isUnlocked: Bool { pct >= profileUnlockThreshold }
    private var progressFraction: CGFloat { min(CGFloat(pct) / 100, 1.0) }

    var body: some View {
        VStack(spacing: 0) {

            // ── Top bar ─────────────────────────────────────────────────────
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    AQLogoView()
                    Text("AI Profile Setup")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(AQ.secondary)
                }
                Spacer()
                // Accuracy badge
                HStack(spacing: 5) {
                    ZStack {
                        Circle()
                            .stroke(isUnlocked ? AQ.green.opacity(0.2) : AQ.secondary.opacity(0.15),
                                    lineWidth: 1.5)
                            .frame(width: 28, height: 28)
                        Circle()
                            .trim(from: 0, to: ringProgress)
                            .stroke(isUnlocked ? AQ.green : AQ.blue,
                                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .frame(width: 28, height: 28)
                            .rotationEffect(.degrees(-90))
                            .animation(.easeInOut(duration: 0.5), value: ringProgress)
                        Text("\(pct)")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(isUnlocked ? AQ.green : AQ.label)
                    }
                    Text("\(pct)%")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isUnlocked ? AQ.green : AQ.secondary)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.3), value: pct)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 56)
            .padding(.bottom, 20)

            // ── Progress strip ──────────────────────────────────────────────
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(AQ.rule)
                    Rectangle()
                        .fill(isUnlocked ? AQ.green : AQ.blue)
                        .frame(width: geo.size.width * progressFraction)
                        .animation(.easeInOut(duration: 0.5), value: progressFraction)
                }
            }
            .frame(height: 3)

            // ── Step roadmap ────────────────────────────────────────────────
            HStack(spacing: 0) {
                StepDot(number: 1, label: "AI Profile", active: true,  done: isUnlocked, color: isUnlocked ? AQ.green : AQ.blue)
                StepConnector(done: isUnlocked)
                StepDot(number: 2, label: "Scan Room",  active: false, done: false, color: AQ.secondary.opacity(0.4))
                StepConnector(done: false)
                StepDot(number: 3, label: "Get Quote",  active: false, done: false, color: AQ.secondary.opacity(0.4))
            }
            .padding(.horizontal, 32)
            .padding(.top, 20)
            .padding(.bottom, 4)

            // ── Question area ───────────────────────────────────────────────
            if isUnlocked {
                UnlockBanner()
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        if engine.answeredCount == 0 {
                            WelcomeBanner()
                                .padding(.horizontal, 24)
                                .padding(.top, 16)
                                .padding(.bottom, 12)
                        }

                        if let question = engine.currentQuestion {
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
                            .padding(.top, 16)
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal:   .move(edge: .leading).combined(with: .opacity)
                            ))
                            .id(question.id)
                        } else if engine.isGeneratingMore {
                            VStack(spacing: 14) {
                                ProgressView().tint(AQ.blue)
                                Text("Loading more questions…")
                                    .font(AQ.body(14))
                                    .foregroundColor(AQ.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(48)
                        }

                        if engine.answeredCount > 0 {
                            AnsweredReviewSection(questions: engine.questions.filter { $0.isAnswered })
                                .padding(.top, 28)
                                .padding(.horizontal, 24)
                        }

                        Color.clear.frame(height: 120)
                    }
                }
            }

            // ── Bottom CTA ──────────────────────────────────────────────────
            VStack(spacing: 0) {
                Divider().background(AQ.rule).padding(.bottom, 16)

                if isUnlocked {
                    Button {
                        // ContentView watches profileReady — transitions automatically
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "lock.open.fill")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Scan Room")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(AQ.green)
                        .cornerRadius(14)
                        .scaleEffect(unlockPulse ? 1.02 : 1.0)
                        .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: unlockPulse)
                    }
                    .padding(.horizontal, 24)
                    .onAppear { unlockPulse = true }
                } else {
                    // Secondary options beneath the active question
                    HStack(spacing: 20) {
                        Button { showDocumentSheet = true } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "doc.badge.plus").font(.system(size: 12, weight: .medium))
                                Text("Upload rate card").font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(AQ.blue)
                        }
                        Text("·").foregroundColor(AQ.rule)
                        Button { withAnimation { engine.loadDemoProfile() } } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "flask").font(.system(size: 12, weight: .medium))
                                Text("Use demo").font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(AQ.secondary)
                        }
                    }
                    .padding(.horizontal, 24)
                }

                // ── Guest entry link ────────────────────────────────────────────
                if let guestTap = onGuestTap {
                    Button(action: guestTap) {
                        HStack(spacing: 6) {
                            Image(systemName: "dot.scope")
                                .font(.system(size: 13, weight: .medium))
                            Text("Just want to scan a room? Try it free →")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(AQ.secondary)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                }

                Color.clear.frame(height: 36)
            }
        }
        .background(Color.white)
        .onAppear { ringProgress = progressFraction }
        .onChange(of: pct) { _ in ringProgress = progressFraction }
        .onTapGesture { inputFocused = false }
        .sheet(isPresented: $showDocumentSheet) {
            AddDocumentSheet(engine: engine)
        }
    }
}

// MARK: - Step Dot & Connector (shared between ProfileGateView and ReadyView)

private struct StepDot: View {
    let number: Int
    let label: String
    let active: Bool
    let done: Bool
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(done ? color : (active ? color.opacity(0.12) : AQ.fill))
                    .frame(width: 28, height: 28)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Text("\(number)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(active ? color : AQ.secondary.opacity(0.5))
                }
            }
            Text(label)
                .font(.system(size: 10, weight: active || done ? .semibold : .regular))
                .foregroundColor(active || done ? (done ? color : AQ.ink) : AQ.secondary.opacity(0.5))
        }
    }
}

private struct StepConnector: View {
    let done: Bool
    var body: some View {
        Rectangle()
            .fill(done ? AQ.green : AQ.rule)
            .frame(height: 1.5)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 22)
            .animation(.easeInOut(duration: 0.4), value: done)
    }
}

// MARK: - Unlock Banner (shown in gate view when threshold reached)

private struct UnlockBanner: View {
    @State private var pulse = false
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(AQ.green.opacity(0.10))
                    .frame(width: 48, height: 48)
                    .scaleEffect(pulse ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: pulse)
                Circle()
                    .fill(AQ.green.opacity(0.18))
                    .frame(width: 34, height: 34)
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AQ.green)
            }
            .onAppear { pulse = true }

            VStack(alignment: .leading, spacing: 5) {
                Text("Your AI is ready to quote.")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AQ.ink)
                Text("Tap Scan Room to measure the space, then speak your job — your AI will produce a ready-to-send quote using your exact rates.")
                    .font(AQ.body(13))
                    .foregroundColor(AQ.secondary)
                    .lineSpacing(4)
            }
        }
        .padding(16)
        .background(AQ.green.opacity(0.04))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AQ.green.opacity(0.18), lineWidth: 1))
    }
}

// MARK: - Step Why Card
// Explains to the user why the current step exists and what it does for them.

private struct StepWhyCard: View {
    let icon: String
    let color: Color
    let headline: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.09))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(headline)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(color)
                    .kerning(0.2)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundColor(AQ.secondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(color.opacity(0.04))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.12), lineWidth: 1))
    }
}

// MARK: - Ready View

struct ReadyView: View {
    @ObservedObject var coordinator: ScanCoordinator
    @EnvironmentObject var questionEngine: QuestionEngine
    var onGuestTap: (() -> Void)? = nil
    @State private var showOnboarding = false
    @State private var showManualEntry = false
    @State private var showHistory = false
    @State private var showProfileMenu = false
    @State private var pulseIcon = false
    @ObservedObject private var historyStore = QuoteHistoryStore.shared

    var isLiDAR: Bool { coordinator.scanMethod == .lidar }

    var body: some View {
        VStack(spacing: 0) {

            // ── Navigation bar ──────────────────────────────────────────────
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    AQLogoView()
                    Text("Room Scanner")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(AQ.secondary)
                }
                Spacer()
                HStack(spacing: 12) {
                    AIProfileButton(
                        answered: questionEngine.answeredCount,
                        pct: questionEngine.personalisation
                    ) { showOnboarding = true }

                    ProfileIconButton(pct: questionEngine.personalisation) {
                        showProfileMenu = true
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 56)
            .padding(.bottom, 20)

            // ── Step roadmap ────────────────────────────────────────────────
            HStack(spacing: 0) {
                StepDot(number: 1, label: "AI Profile", active: false, done: true,  color: AQ.green)
                StepConnector(done: true)
                StepDot(number: 2, label: "Scan Room",  active: true,  done: false, color: AQ.blue)
                StepConnector(done: false)
                StepDot(number: 3, label: "Get Quote",  active: false, done: false, color: AQ.secondary.opacity(0.4))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 16)

            // ── Profile hint strip ─────────────────────────────────────────
            if questionEngine.answeredCount > 0 {
                let trade    = questionEngine.profile.trade
                let rate     = questionEngine.profile.answers.first(where: { $0.id == "day_rate" })?.answer ?? ""
                let supplier = questionEngine.profile.answers.first(where: { $0.id == "supplier" })?.answer ?? ""
                let parts = [trade, rate, supplier].filter { !$0.isEmpty }
                if !parts.isEmpty {
                    Button { showOnboarding = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(AQ.green)
                            Text("Quote will use: \(parts.joined(separator: " · "))")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(AQ.secondary)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "pencil")
                                .font(.system(size: 10))
                                .foregroundColor(AQ.secondary.opacity(0.5))
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)
                    }
                }
            }

            Divider().background(AQ.rule).padding(.horizontal, 24)

            Spacer()

            // ── Hero icon ───────────────────────────────────────────────────
            ZStack {
                Circle()
                    .stroke(AQ.blue.opacity(0.07), lineWidth: 1)
                    .frame(width: 160, height: 160)
                Circle()
                    .stroke(AQ.blue.opacity(0.13), lineWidth: 1)
                    .frame(width: 118, height: 118)
                Circle()
                    .fill(AQ.fill)
                    .frame(width: 78, height: 78)
                Image(systemName: isLiDAR ? "cube.transparent" : "camera.aperture")
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(AQ.blue)
                    .scaleEffect(pulseIcon ? 1.06 : 1.0)
                    .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true),
                               value: pulseIcon)
            }
            .onAppear { pulseIcon = true }
            .padding(.bottom, 28)

            Text("Measure the room.")
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(AQ.ink)
                .padding(.bottom, 8)

            Text(isLiDAR
                 ? "LiDAR maps every surface. Walk the room, tap Done."
                 : "No LiDAR? Sweep the camera or type your tape measure readings.")
                .font(AQ.body(15))
                .foregroundColor(AQ.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .padding(.horizontal, 40)

            ScanMethodBadge(method: coordinator.scanMethod)
                .padding(.top, 14)

            Spacer()

            // ── CTA ─────────────────────────────────────────────────────────
            VStack(spacing: 0) {
                Divider().background(AQ.rule).padding(.bottom, 20)

                // Primary CTAs
                HStack(spacing: 10) {
                    Button { coordinator.startScan() } label: {
                        Text(isLiDAR ? "Start LiDAR Scan" : "Sweep Room")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 17)
                            .background(AQ.blue)
                            .cornerRadius(14)
                    }
                    Button { showManualEntry = true } label: {
                        VStack(spacing: 3) {
                            Image(systemName: "ruler")
                                .font(.system(size: 14, weight: .medium))
                            Text("I have the\nmeasurements")
                                .font(.system(size: 12, weight: .medium))
                                .multilineTextAlignment(.center)
                        }
                        .foregroundColor(AQ.ink)
                        .frame(width: 88)
                        .padding(.vertical, 14)
                        .background(AQ.fill)
                        .cornerRadius(14)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AQ.rule, lineWidth: 1))
                    }
                }
                .padding(.horizontal, 24)

                // Secondary options
                HStack(spacing: 20) {
                    // manual entry promoted above
                    #if DEBUG
                    Button {
                        coordinator.submitManual(length: 4.8, width: 3.6, height: 2.4)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "flask").font(.system(size: 12))
                            Text("Use demo").font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(AQ.secondary)
                    }
                    #endif
                }
                .padding(.top, 16)

                if let guestTap = onGuestTap {
                    Button(action: guestTap) {
                        HStack(spacing: 5) {
                            Image(systemName: "dot.scope").font(.system(size: 12))
                            Text("Just want to scan a room? Try it free →")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(AQ.secondary)
                    }
                    .padding(.top, 4)
                }

                Color.clear.frame(height: 28)
            }
        }
        .background(Color.white)
        .sheet(isPresented: $showOnboarding) {
            OnboardingSheet().environmentObject(questionEngine)
        }
        .sheet(isPresented: $showManualEntry) {
            ManualEntrySheet(coordinator: coordinator)
        }
        .sheet(isPresented: $showHistory) {
            QuoteHistoryView(store: historyStore)
        }
        .sheet(isPresented: $showProfileMenu) {
            ProfileMenuSheet().environmentObject(questionEngine)
        }
        .onReceive(NotificationCenter.default.publisher(for: .aqSignOut)) { _ in
            showProfileMenu = false
            questionEngine.resetProfile()
        }
    }
}

// MARK: - Non-LiDAR method cards

struct NonLiDARMethodCards: View {
    let onSweep: () -> Void
    let onManual: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            // Camera sweep
            Button(action: onSweep) {
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(AQ.blue.opacity(0.08))
                            .frame(width: 44, height: 44)
                        Image(systemName: "camera.aperture")
                            .font(.system(size: 18, weight: .light))
                            .foregroundColor(AQ.blue)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Sweep Room")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AQ.ink)
                        Text("Walk around pointing camera at every wall · ±5–10cm")
                            .font(AQ.body(12))
                            .foregroundColor(AQ.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AQ.secondary.opacity(0.5))
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(AQ.blue.opacity(0.25), lineWidth: 1)
                )
            }

            // Manual entry
            Button(action: onManual) {
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(AQ.green.opacity(0.08))
                            .frame(width: 44, height: 44)
                        Image(systemName: "ruler")
                            .font(.system(size: 18, weight: .light))
                            .foregroundColor(AQ.green)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Enter Manually")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AQ.ink)
                        Text("Type tape measure readings · exact accuracy")
                            .font(AQ.body(12))
                            .foregroundColor(AQ.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AQ.secondary.opacity(0.5))
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(AQ.green.opacity(0.25), lineWidth: 1)
                )
            }
        }
    }
}

// MARK: - Manual Entry Sheet

struct ManualEntrySheet: View {
    @ObservedObject var coordinator: ScanCoordinator
    @Environment(\.dismiss) var dismiss

    @State private var lengthText = ""
    @State private var widthText  = ""
    @State private var heightText = "2.4"
    @State private var showCustomShape = false
    @FocusState private var focused: Field?

    enum Field { case length, width, height }

    var length: Double? { Double(lengthText.replacingOccurrences(of: ",", with: ".")) }
    var width:  Double? { Double(widthText.replacingOccurrences(of: ",", with: "."))  }
    var height: Double? { Double(heightText.replacingOccurrences(of: ",", with: ".")) }
    var canSubmit: Bool { length != nil && width != nil && height != nil }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Instruction
                VStack(spacing: 6) {
                    Text("Enter Room Measurements")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(AQ.ink)
                    Text("Use a tape measure for best accuracy.")
                        .font(AQ.body(14))
                        .foregroundColor(AQ.secondary)
                }
                .padding(.top, 32)
                .padding(.bottom, 36)

                // Diagram
                RoomDiagramView()
                    .padding(.horizontal, 48)
                    .padding(.bottom, 36)

                // Inputs
                VStack(spacing: 14) {
                    MeasurementField(
                        label: "Length",
                        hint: "e.g. 4.5",
                        unit: "m",
                        text: $lengthText,
                        focused: $focused,
                        field: .length,
                        next: { focused = .width }
                    )
                    MeasurementField(
                        label: "Width",
                        hint: "e.g. 3.2",
                        unit: "m",
                        text: $widthText,
                        focused: $focused,
                        field: .width,
                        next: { focused = .height }
                    )
                    MeasurementField(
                        label: "Ceiling height",
                        hint: "e.g. 2.4",
                        unit: "m",
                        text: $heightText,
                        focused: $focused,
                        field: .height,
                        next: { focused = nil }
                    )
                }
                .padding(.horizontal, 24)

                Spacer()

                // CTA
                VStack(spacing: 0) {
                    Divider().background(AQ.rule).padding(.bottom, 20)
                    Button {
                        guard let l = length, let w = width, let h = height else { return }
                        coordinator.submitManual(length: l, width: w, height: h)
                        dismiss()
                    } label: {
                        Text("Calculate Quote")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 17)
                            .background(canSubmit ? AQ.blue : AQ.blue.opacity(0.35))
                            .cornerRadius(14)
                    }
                    .disabled(!canSubmit)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)

                    // Custom shape option
                    Button {
                        focused = nil
                        showCustomShape = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "pentagon")
                                .font(.system(size: 13, weight: .medium))
                            Text("Different room shape?  Draw it instead")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(AQ.secondary)
                    }
                    .padding(.bottom, 36)
                }
            }
            .background(Color.white)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(AQ.secondary)
                }
            }
            .sheet(isPresented: $showCustomShape) {
                CustomShapeSheet(coordinator: coordinator, parentDismiss: dismiss)
            }
        }
        .onTapGesture { focused = nil }
    }
}

// MARK: - Room diagram (simple top-down illustration)

struct RoomDiagramView: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                // Room outline
                Rectangle()
                    .stroke(AQ.rule, lineWidth: 1.5)
                    .frame(width: w, height: h)

                // Length arrow (horizontal)
                ArrowLine(start: CGPoint(x: 12, y: h/2),
                          end:   CGPoint(x: w - 12, y: h/2))
                    .stroke(AQ.blue, lineWidth: 1)
                Text("Length")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AQ.blue)
                    .position(x: w/2, y: h/2 - 12)

                // Width arrow (vertical)
                ArrowLine(start: CGPoint(x: w/2, y: 12),
                          end:   CGPoint(x: w/2, y: h - 12))
                    .stroke(AQ.secondary, lineWidth: 1)
                Text("Width")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AQ.secondary)
                    .position(x: w/2 + 28, y: h/2)
                    .rotationEffect(.degrees(90))
            }
        }
        .frame(height: 100)
    }
}

struct ArrowLine: Shape {
    let start: CGPoint, end: CGPoint
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: start); p.addLine(to: end)
        // Arrowhead at end
        let angle = atan2(end.y - start.y, end.x - start.x)
        let size: CGFloat = 6
        p.move(to: end)
        p.addLine(to: CGPoint(x: end.x - size * cos(angle - 0.4),
                              y: end.y - size * sin(angle - 0.4)))
        p.move(to: end)
        p.addLine(to: CGPoint(x: end.x - size * cos(angle + 0.4),
                              y: end.y - size * sin(angle + 0.4)))
        // Arrowhead at start
        let angle2 = atan2(start.y - end.y, start.x - end.x)
        p.move(to: start)
        p.addLine(to: CGPoint(x: start.x - size * cos(angle2 - 0.4),
                              y: start.y - size * sin(angle2 - 0.4)))
        p.move(to: start)
        p.addLine(to: CGPoint(x: start.x - size * cos(angle2 + 0.4),
                              y: start.y - size * sin(angle2 + 0.4)))
        return p
    }
}

// MARK: - Custom Shape Sheet
// Users draw a floor plan by tapping to add vertices. Drag to reposition.
// Vertices are shown in metres based on a configurable scale.

struct CustomShapeSheet: View {
    @ObservedObject var coordinator: ScanCoordinator
    let parentDismiss: DismissAction
    @Environment(\.dismiss) var dismiss

    // Canvas vertices in canvas-point coordinates
    @State private var vertices: [CGPoint] = []
    @State private var dragIndex: Int? = nil
    @State private var heightText: String = "2.4"
    @State private var canvasSize: CGSize = .zero
    @FocusState private var heightFocused: Bool

    // metres per canvas point — 1 canvas point = metersPerPoint metres
    // We use a 10m × 10m room space mapped to the canvas
    let metersPerPoint: Double = 10.0 / 300.0   // 300pt canvas = 10m

    var height: Double { Double(heightText.replacingOccurrences(of: ",", with: ".")) ?? 2.4 }
    var canSubmit: Bool { vertices.count >= 3 }

    // Vertex positions in metres
    var verticesInMetres: [CGPoint] {
        vertices.map { CGPoint(x: Double($0.x) * metersPerPoint,
                               y: Double($0.y) * metersPerPoint) }
    }

    // Wall segments for label display
    func wallLength(_ i: Int) -> Double {
        let a = verticesInMetres[i]
        let b = verticesInMetres[(i + 1) % vertices.count]
        let dx = Double(a.x - b.x), dy = Double(a.y - b.y)
        return sqrt(dx*dx + dy*dy)
    }

    func midpoint(_ i: Int) -> CGPoint {
        let a = vertices[i], b = vertices[(i + 1) % vertices.count]
        return CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {

                // Instructions
                VStack(spacing: 4) {
                    Text("Draw Your Room Shape")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(AQ.ink)
                    Text("Tap the canvas to add corners. Drag a point to reposition it. Tap a point to remove it.")
                        .font(AQ.body(13))
                        .foregroundColor(AQ.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.top, 28)
                .padding(.bottom, 16)

                // Scale legend
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(AQ.blue)
                        .frame(width: 30, height: 2)
                    Text("= 1 m")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AQ.secondary)
                    Spacer()
                    if vertices.count >= 3 {
                        let area = polygonArea(verticesInMetres)
                        Text(String(format: "Area: %.1f m²", area))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AQ.green)
                    }
                    if vertices.count < 3 {
                        Text("Add at least 3 corners")
                            .font(.system(size: 12))
                            .foregroundColor(AQ.secondary.opacity(0.7))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)

                // ── Drawing canvas ────────────────────────────────────────────
                GeometryReader { geo in
                    ZStack {
                        // Background grid
                        CanvasGrid(size: geo.size, metersPerPoint: metersPerPoint)

                        // Polygon fill
                        if vertices.count >= 3 {
                            PolygonShape(points: vertices)
                                .fill(AQ.blue.opacity(0.07))
                            PolygonShape(points: vertices)
                                .stroke(AQ.blue, lineWidth: 2)
                        } else if vertices.count == 2 {
                            Path { p in
                                p.move(to: vertices[0])
                                p.addLine(to: vertices[1])
                            }
                            .stroke(AQ.blue, lineWidth: 2)
                        }

                        // Closing line (last → first) hint
                        if vertices.count >= 3 {
                            Path { p in
                                p.move(to: vertices.last!)
                                p.addLine(to: vertices.first!)
                            }
                            .stroke(AQ.blue.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        }

                        // Wall length labels
                        if vertices.count >= 2 {
                            ForEach(0..<vertices.count, id: \.self) { i in
                                if i < vertices.count - 1 || vertices.count >= 3 {
                                    let mp = midpoint(i)
                                    let len = wallLength(i)
                                    Text(String(format: "%.1fm", len))
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(AQ.blue)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(Color.white.opacity(0.85))
                                        .cornerRadius(4)
                                        .position(mp)
                                }
                            }
                        }

                        // Vertex dots
                        ForEach(0..<vertices.count, id: \.self) { i in
                            Circle()
                                .fill(dragIndex == i ? AQ.amber : AQ.blue)
                                .frame(width: dragIndex == i ? 20 : 14,
                                       height: dragIndex == i ? 20 : 14)
                                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                                .shadow(radius: 2)
                                .position(vertices[i])
                                // Tap to remove
                                .onTapGesture {
                                    vertices.remove(at: i)
                                }
                        }

                        // Vertex index labels
                        ForEach(0..<vertices.count, id: \.self) { i in
                            Text("\(i + 1)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .position(vertices[i])
                        }
                    }
                    .background(AQ.fill)
                    .cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(AQ.rule, lineWidth: 1))
                    .contentShape(Rectangle())
                    // ── Tap to add vertex ────────────────────────────────────
                    .onTapGesture { location in
                        // If near an existing vertex, don't add (tap handled by vertex layer)
                        let hitRadius: CGFloat = 18
                        let nearExisting = vertices.contains { v in
                            hypot(v.x - location.x, v.y - location.y) < hitRadius
                        }
                        if !nearExisting {
                            vertices.append(location)
                        }
                    }
                    // ── Drag to reposition vertex ────────────────────────────
                    .gesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { value in
                                if dragIndex == nil {
                                    // Find nearest vertex within 24pt
                                    let loc = value.startLocation
                                    dragIndex = vertices.indices.min {
                                        hypot(vertices[$0].x - loc.x, vertices[$0].y - loc.y) <
                                        hypot(vertices[$1].x - loc.x, vertices[$1].y - loc.y)
                                    }.flatMap { i in
                                        hypot(vertices[i].x - loc.x, vertices[i].y - loc.y) < 24 ? i : nil
                                    }
                                }
                                if let i = dragIndex {
                                    let clamped = CGPoint(
                                        x: max(8, min(geo.size.width - 8, value.location.x)),
                                        y: max(8, min(geo.size.height - 8, value.location.y))
                                    )
                                    vertices[i] = clamped
                                }
                            }
                            .onEnded { _ in dragIndex = nil }
                    )
                }
                .padding(.horizontal, 16)
                .frame(height: 300)

                // Quick shape presets
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ShapePresetButton(label: "L-shape") {
                            vertices = lShapePreset()
                        }
                        ShapePresetButton(label: "T-shape") {
                            vertices = tShapePreset()
                        }
                        ShapePresetButton(label: "Pentagon") {
                            vertices = regularPolygon(sides: 5, in: CGSize(width: 280, height: 280))
                        }
                        ShapePresetButton(label: "Hexagon") {
                            vertices = regularPolygon(sides: 6, in: CGSize(width: 280, height: 280))
                        }
                        ShapePresetButton(label: "Clear") {
                            vertices = []
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 12)

                // Height input
                HStack {
                    Text("Ceiling height")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AQ.secondary)
                    Spacer()
                    TextField("2.4", text: $heightText)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(AQ.ink)
                        .keyboardType(.decimalPad)
                        .focused($heightFocused)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                    Text("m")
                        .font(.system(size: 15))
                        .foregroundColor(AQ.secondary)
                        .padding(.leading, 4)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 12).stroke(AQ.rule, lineWidth: 1))
                .padding(.horizontal, 16)

                Spacer()

                // CTA
                VStack(spacing: 0) {
                    Divider().background(AQ.rule).padding(.bottom, 16)
                    Button {
                        coordinator.submitCustomShape(
                            vertices: verticesInMetres,
                            scale: 1.0,
                            height: height
                        )
                        dismiss()
                        parentDismiss()
                    } label: {
                        Text("Use This Shape")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 17)
                            .background(canSubmit ? AQ.blue : AQ.blue.opacity(0.35))
                            .cornerRadius(14)
                    }
                    .disabled(!canSubmit)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 36)
                }
            }
            .background(Color.white)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Back") { dismiss() }
                        .foregroundColor(AQ.secondary)
                }
            }
            .onTapGesture { heightFocused = false }
        }
    }

    // MARK: - Geometry helpers

    func polygonArea(_ pts: [CGPoint]) -> Double {
        let n = pts.count
        var sum: Double = 0
        for i in 0..<n {
            let j = (i + 1) % n
            sum += Double(pts[i].x) * Double(pts[j].y)
            sum -= Double(pts[j].x) * Double(pts[i].y)
        }
        return abs(sum) / 2.0
    }

    func regularPolygon(sides: Int, in size: CGSize) -> [CGPoint] {
        let cx = size.width / 2, cy = size.height / 2
        let r = min(cx, cy) * 0.75
        return (0..<sides).map { i in
            let angle = Double(i) * 2 * .pi / Double(sides) - .pi / 2
            return CGPoint(x: cx + r * cos(angle), y: cy + r * sin(angle))
        }
    }

    func lShapePreset() -> [CGPoint] {
        // L-shape fitted in ~280×280 canvas area
        let s: CGFloat = 140
        return [
            CGPoint(x: 50, y: 50),
            CGPoint(x: 50 + s, y: 50),
            CGPoint(x: 50 + s, y: 50 + s * 0.5),
            CGPoint(x: 50 + s * 0.5, y: 50 + s * 0.5),
            CGPoint(x: 50 + s * 0.5, y: 50 + s),
            CGPoint(x: 50, y: 50 + s),
        ]
    }

    func tShapePreset() -> [CGPoint] {
        let s: CGFloat = 130
        return [
            CGPoint(x: 50, y: 50),
            CGPoint(x: 50 + s, y: 50),
            CGPoint(x: 50 + s, y: 50 + s * 0.4),
            CGPoint(x: 50 + s * 0.7, y: 50 + s * 0.4),
            CGPoint(x: 50 + s * 0.7, y: 50 + s),
            CGPoint(x: 50 + s * 0.3, y: 50 + s),
            CGPoint(x: 50 + s * 0.3, y: 50 + s * 0.4),
            CGPoint(x: 50, y: 50 + s * 0.4),
        ]
    }
}

// MARK: - Supporting shapes for CustomShapeSheet

struct PolygonShape: Shape {
    let points: [CGPoint]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard points.count >= 2 else { return p }
        p.move(to: points[0])
        points.dropFirst().forEach { p.addLine(to: $0) }
        p.closeSubpath()
        return p
    }
}

struct CanvasGrid: View {
    let size: CGSize
    let metersPerPoint: Double
    var body: some View {
        let step = CGFloat(1.0 / metersPerPoint)  // points per 1 metre
        Canvas { ctx, sz in
            var x: CGFloat = 0
            while x <= sz.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: sz.height))
                ctx.stroke(path, with: .color(AQ.rule.opacity(0.6)), lineWidth: 0.5)
                x += step
            }
            var y: CGFloat = 0
            while y <= sz.height {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: sz.width, y: y))
                ctx.stroke(path, with: .color(AQ.rule.opacity(0.6)), lineWidth: 0.5)
                y += step
            }
        }
    }
}

struct ShapePresetButton: View {
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AQ.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(AQ.fill)
                .cornerRadius(20)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(AQ.rule, lineWidth: 1))
        }
    }
}

// MARK: - Measurement input field

struct MeasurementField: View {
    let label: String
    let hint: String
    let unit: String
    @Binding var text: String
    var focused: FocusState<ManualEntrySheet.Field?>.Binding
    let field: ManualEntrySheet.Field
    let next: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AQ.secondary)
                .frame(width: 110, alignment: .leading)
            TextField(hint, text: $text)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(AQ.ink)
                .keyboardType(.decimalPad)
                .focused(focused, equals: field)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity)
            Text(unit)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(AQ.secondary)
                .padding(.leading, 6)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(focused.wrappedValue == field ? AQ.blue : AQ.rule, lineWidth: 1)
                .animation(.easeInOut(duration: 0.15), value: focused.wrappedValue == field)
        )
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
        case .poseFusion: PoseFusionScanningView(coordinator: coordinator)
        case .manual:     EmptyView()  // manual never enters .scanning state
        }
    }
}

// MARK: - LiDAR Scanning View

struct LiDARScanningView: View {
    @ObservedObject var coordinator: ScanCoordinator
    var body: some View {
        LiDARHostRepresentable(coordinator: coordinator)
            .ignoresSafeArea()
    }
}

// MARK: - Pose Fusion Scanning View

struct PoseFusionScanningView: View {
    @ObservedObject var coordinator: ScanCoordinator
    @State private var isHolding = false
    @State private var showTutorial = !UserDefaults.standard.bool(forKey: "aq_posefusion_tutorial_seen")

    var body: some View {
        ZStack(alignment: .bottom) {
            if coordinator.arSession != nil {
                ARHostRepresentable(coordinator: coordinator).ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(isHolding ? Color.red : Color.white.opacity(0.5))
                            .frame(width: 6, height: 6)
                            .animation(.easeInOut(duration: 0.3), value: isHolding)
                        Text(isHolding
                             ? String(format: "%.1fm", coordinator.scanProgress * 4.0)
                             : "Ready")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(22)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)

                Spacer()

                // Coverage ring — appears while holding
                if isHolding {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.12), lineWidth: 2)
                            .frame(width: 120, height: 120)
                        Circle()
                            .trim(from: 0, to: CGFloat(coordinator.scanProgress))
                            .stroke(Color.white,
                                    style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .frame(width: 120, height: 120)
                            .rotationEffect(.degrees(-90))
                            .animation(.easeInOut(duration: 0.3), value: coordinator.scanProgress)
                        VStack(spacing: 2) {
                            Text("\(Int(coordinator.scanProgress * 100))%")
                                .font(.system(size: 22, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                            Text("coverage")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    .padding(.bottom, 20)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }

                ScanHUD(coordinator: coordinator)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)

                // Hold-to-scan button
                HoldToScanButton(isHolding: $isHolding) {
                    withAnimation(.easeInOut(duration: 0.15)) { isHolding = true }
                } onRelease: {
                    withAnimation(.easeInOut(duration: 0.15)) { isHolding = false }
                    coordinator.stopScan()
                }
                .padding(.bottom, 48)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.2), value: isHolding)
        .overlay {
            if showTutorial {
                ZStack {
                    Color.black.opacity(0.55).ignoresSafeArea()
                    ScanTutorialAnimation()
                        .padding(.bottom, 140)
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation(.easeOut(duration: 0.4)) { showTutorial = false }
                        UserDefaults.standard.set(true, forKey: "aq_posefusion_tutorial_seen")
                    }
                }
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.3)) { showTutorial = false }
                    UserDefaults.standard.set(true, forKey: "aq_posefusion_tutorial_seen")
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showTutorial)
    }
}

// MARK: - Scan Tutorial Animation

private struct ScanTutorialAnimation: View {
    @State private var sweepOffset: CGFloat = -40
    @State private var sweepOpacity: Double = 0

    var body: some View {
        VStack(spacing: 28) {
            ZStack {
                // Sweep arcs
                ForEach(0..<3) { i in
                    Capsule()
                        .fill(Color.white.opacity(0.15 - Double(i) * 0.04))
                        .frame(width: 3, height: 40 + CGFloat(i) * 16)
                        .offset(x: sweepOffset + CGFloat(i) * 6)
                        .animation(
                            .easeInOut(duration: 1.4).repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.08),
                            value: sweepOffset
                        )
                }
                // Phone icon
                Image(systemName: "iphone")
                    .font(.system(size: 48, weight: .ultraLight))
                    .foregroundColor(.white)
                    .rotationEffect(.degrees(90))
                    .offset(x: sweepOffset)
                    .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: sweepOffset)
            }
            .frame(width: 160, height: 100)
            .opacity(sweepOpacity)

            VStack(spacing: 8) {
                Text("Hold & sweep slowly")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                HStack(spacing: 6) {
                    Image(systemName: "hand.point.down.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                    Text("Hold the button below")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .onAppear {
            withAnimation(.easeIn(duration: 0.4)) { sweepOpacity = 1 }
            sweepOffset = 40
        }
    }
}

// MARK: - Hold-to-scan button

struct HoldToScanButton: View {
    @Binding var isHolding: Bool
    let onPress: () -> Void
    let onRelease: () -> Void

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(isHolding ? 0.25 : 0.0), lineWidth: 2)
                .frame(width: 88, height: 88)
                .scaleEffect(isHolding ? 1.18 : 1.0)
                .animation(
                    isHolding
                        ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                        : .easeInOut(duration: 0.2),
                    value: isHolding
                )
            Circle()
                .fill(isHolding ? Color.white : Color.white.opacity(0.85))
                .frame(width: 68, height: 68)
                .scaleEffect(isHolding ? 0.88 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isHolding)
            Image(systemName: isHolding ? "stop.fill" : "record.circle")
                .font(.system(size: isHolding ? 18 : 22, weight: .medium))
                .foregroundColor(isHolding ? Color.red : AQ.ink)
                .animation(.easeInOut(duration: 0.15), value: isHolding)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isHolding { onPress() } }
                .onEnded   { _ in if isHolding  { onRelease() } }
        )
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
    @State private var showJobDescription = false
    @State private var roomTypeOverride = ""

    private func isSelected(_ type: String) -> Bool {
        if roomTypeOverride.isEmpty {
            return result.roomType.lowercased() == type.lowercased()
        }
        return roomTypeOverride.lowercased() == type.lowercased()
    }

    var effectiveRoomType: String { roomTypeOverride.isEmpty ? result.roomType : roomTypeOverride }

    var body: some View {
        VStack(spacing: 0) {

            // Header
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    AQLogoView()
                    Text("Room measured")
                        .font(.system(size: 12))
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
            .padding(.bottom, 20)

            Divider().background(AQ.rule).padding(.horizontal, 24).padding(.bottom, 16)

            // Room type picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(["Kitchen", "Bathroom", "Living room", "Bedroom", "Other"], id: \.self) { type in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { roomTypeOverride = type }
                        } label: {
                            Text(type)
                                .font(.system(size: 13, weight: isSelected(type) ? .semibold : .medium))
                                .foregroundColor(isSelected(type) ? .white : AQ.ink)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(isSelected(type) ? AQ.blue : AQ.fill)
                                .cornerRadius(20)
                                .overlay(RoundedRectangle(cornerRadius: 20).stroke(isSelected(type) ? AQ.blue : AQ.rule, lineWidth: 1))
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 16)

            // Dimensions card
            VStack(spacing: 0) {
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
                .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 20)

                Divider().background(AQ.rule).padding(.horizontal, 20)

                HStack(spacing: 0) {
                    DimensionCell(label: "Length", value: result.lengthStr, unit: "m")
                    Divider().frame(height: 60).background(AQ.rule)
                    DimensionCell(label: "Width",  value: result.widthStr,  unit: "m")
                    Divider().frame(height: 60).background(AQ.rule)
                    DimensionCell(label: "Height", value: result.heightStr, unit: "m")
                }
                .padding(.vertical, 4)

                Divider().background(AQ.rule).padding(.horizontal, 20)

                HStack(spacing: 0) {
                    StatCell(label: "Floor area", value: "\(result.floorAreaStr) m²")
                    Divider().frame(height: 44).background(AQ.rule)
                    StatCell(label: "Doors",    value: "\(result.doorCount)")
                    Divider().frame(height: 44).background(AQ.rule)
                    StatCell(label: "Windows",  value: "\(result.windowCount)")
                }
                .padding(.vertical, 4).padding(.bottom, 8)
            }
            .background(Color.white)
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AQ.rule, lineWidth: 1))
            .padding(.horizontal, 24)

            Spacer()

            // CTAs
            VStack(spacing: 0) {
                Divider().background(AQ.rule).padding(.bottom, 20)

                Button { showJobDescription = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Describe the Job")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(AQ.blue)
                    .cornerRadius(14)
                }
                .padding(.horizontal, 24)

                Button { coordinator.reset() } label: {
                    Text("Rescan")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AQ.secondary)
                }
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
        }
        .background(AQ.fill)
        .fullScreenCover(isPresented: $showJobDescription) {
            JobDescriptionView(result: result, coordinator: coordinator, roomTypeOverride: effectiveRoomType)
        }
    }
}

// MARK: - Job Description View

struct JobDescriptionView: View {
    let result: RoomDimensions
    @ObservedObject var coordinator: ScanCoordinator
    var roomTypeOverride: String = ""
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var questionEngine: QuestionEngine

    @StateObject private var recorder = VoiceRecorder()
    @State private var jobDescription = ""
    @State private var customerName   = ""
    @State private var showQuote      = false
    @State private var showVoicePanel = false
    @State private var showQuickSetup = false
    @FocusState private var typeFocused: Bool

    private var effectiveRoomType: String { roomTypeOverride.isEmpty ? result.roomType : roomTypeOverride }

    var canProceed: Bool { jobDescription.trimmingCharacters(in: .whitespaces).count > 10 }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {

                        // Room pill
                        HStack(spacing: 8) {
                            Image(systemName: "cube.transparent")
                                .font(.system(size: 12)).foregroundColor(AQ.blue)
                            Text("\(result.lengthStr) × \(result.widthStr) × \(result.heightStr)m · \(result.floorAreaStr)m² · \(effectiveRoomType.capitalized)")
                                .font(.system(size: 12, weight: .medium)).foregroundColor(AQ.blue)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(AQ.blue.opacity(0.07)).cornerRadius(20)
                        .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 28)

                        Text("What's the job?")
                            .font(.system(size: 32, weight: .bold)).foregroundColor(AQ.ink)
                            .padding(.horizontal, 24).padding(.bottom, 6)

                        Text("Just talk — describe the job out loud.")
                            .font(AQ.body(15)).foregroundColor(AQ.secondary)
                            .lineSpacing(4).padding(.horizontal, 24).padding(.bottom, 20)

                        // ── Text input (default) with mic button in corner ────
                        ZStack(alignment: .bottomTrailing) {
                            ZStack(alignment: .topLeading) {
                                if jobDescription.isEmpty {
                                    Text("e.g. Replace consumer unit, add 3 double sockets, install LED downlights. Old wiring throughout.")
                                        .font(.system(size: 15))
                                        .foregroundColor(AQ.secondary.opacity(0.55))
                                        .padding(16).allowsHitTesting(false)
                                }
                                TextEditor(text: $jobDescription)
                                    .font(.system(size: 15)).foregroundColor(AQ.ink)
                                    .focused($typeFocused)
                                    .frame(minHeight: 140)
                                    .padding(12)
                                    .padding(.trailing, 44) // space for mic button
                                    .scrollContentBackground(.hidden)
                            }
                            .background(AQ.fill).cornerRadius(14)
                            .overlay(RoundedRectangle(cornerRadius: 14)
                                .stroke(typeFocused ? AQ.blue : AQ.rule, lineWidth: 1)
                                .animation(.easeInOut(duration: 0.15), value: typeFocused))

                            // Mic button overlay
                            Button {
                                typeFocused = false
                                showVoicePanel.toggle()
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(recorder.isRecording ? AQ.blue : Color.white)
                                        .frame(width: 34, height: 34)
                                        .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 1)
                                    Image(systemName: recorder.isRecording ? "waveform" : "mic")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(recorder.isRecording ? .white : AQ.secondary)
                                }
                            }
                            .padding(8)
                        }
                        .padding(.horizontal, 24).padding(.bottom, 8)

                        // ── Voice panel (collapsible) ─────────────────────────
                        if showVoicePanel {
                            VoiceInputCard(
                                recorder: recorder,
                                transcript: $jobDescription
                            )
                            .padding(.horizontal, 24).padding(.bottom, 16)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        // Customer name
                        FieldLabel("Customer name (optional)")
                        TextField("e.g. Mr Smith — 14 Oak Street", text: $customerName)
                            .font(.system(size: 16))
                            .padding(.horizontal, 16).padding(.vertical, 14)
                            .background(AQ.fill).cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AQ.rule, lineWidth: 1))
                            .padding(.horizontal, 24).padding(.bottom, 32)

                        Color.clear.frame(height: 100)
                    }
                }

                // ── Bottom bar ───────────────────────────────────────────────
                VStack(spacing: 0) {
                    Divider().background(AQ.rule)

                    // Primary CTA
                    Button {
                        typeFocused = false
                        if questionEngine.personalisation < profileQuickSetupThreshold {
                            showQuickSetup = true
                        } else {
                            showQuote = true
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Generate Quote")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundColor(canProceed ? .white : AQ.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(canProceed ? AQ.blue : AQ.fill)
                        .cornerRadius(14)
                        .animation(.easeInOut(duration: 0.15), value: canProceed)
                    }
                    .disabled(!canProceed)
                    .padding(.horizontal, 24).padding(.top, 14)

                    // Secondary options
                    HStack(spacing: 20) {
                        #if DEBUG
                        Button {
                            jobDescription = "Full rewire of a 3-bed semi. Strip out all old wiring, first and second fix throughout. 14 double sockets, 10 single sockets, 12 LED downlights in kitchen and bathrooms, new consumer unit with RCDs, outside socket and PIR flood light. Old plaster in good condition — no re-plastering needed. Customer has already cleared the rooms."
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "flask").font(.system(size: 12))
                                Text("Use demo").font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(AQ.secondary)
                        }
                        #endif
                    }
                    .padding(.top, 12).padding(.bottom, 28)
                    .background(Color.white)
                }
            }
            .background(Color.white)
            .navigationTitle("Job Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Back") { dismiss() }
                        .foregroundColor(AQ.secondary)
                }
            }
            .onAppear {
                guard jobDescription.isEmpty else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    showVoicePanel = true
                    recorder.toggle()
                }
            }
        }
        .fullScreenCover(isPresented: $showQuote) {
            QuoteView(result: result, jobDescription: jobDescription,
                      customerName: customerName, coordinator: coordinator)
                .environmentObject(questionEngine)
        }
        .sheet(isPresented: $showQuickSetup) {
            QuickSetupSheet(onContinue: {
                showQuickSetup = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showQuote = true
                }
            })
            .environmentObject(questionEngine)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .onTapGesture { typeFocused = false }
        .onReceive(recorder.$transcript) { t in
            if !t.isEmpty { jobDescription = t }
        }
    }
}

// MARK: - Quick Setup Sheet
// Shown before first quote when profile is thin (< 50%).
// Surfaces the 3 most impactful unanswered questions.

private struct QuickSetupSheet: View {
    let onContinue: () -> Void
    @EnvironmentObject var engine: QuestionEngine

    // Top 3 unanswered foundation questions by impact order
    private var unanswered: [OnboardingQuestion] {
        let priority = ["trade", "day_rate", "region", "vat", "what_included", "material_markup"]
        let answered = Set(engine.questions.filter { $0.isAnswered }.map { $0.id })
        return priority.compactMap { id in
            engine.questions.first(where: { $0.id == id && !answered.contains(id) })
        }.prefix(3).map { $0 }
    }

    @State private var answers: [String: String] = [:]
    @State private var currentIdx = 0

    private var currentQ: OnboardingQuestion? {
        guard currentIdx < unanswered.count else { return nil }
        return unanswered[currentIdx]
    }

    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("Quick setup")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(AQ.ink)
                Text("Answer \(unanswered.count) quick question\(unanswered.count == 1 ? "" : "s") for a more accurate quote — takes 30 seconds.")
                    .font(AQ.body(14))
                    .foregroundColor(AQ.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 32)

                // Progress dots
                HStack(spacing: 6) {
                    ForEach(0..<unanswered.count, id: \.self) { i in
                        Circle()
                            .fill(i <= currentIdx ? AQ.blue : AQ.rule)
                            .frame(width: 6, height: 6)
                            .animation(.easeInOut(duration: 0.2), value: currentIdx)
                    }
                }
                .padding(.top, 4)
            }
            .padding(.top, 28)
            .padding(.bottom, 24)

            Divider().background(AQ.rule)

            if let q = currentQ {
                VStack(alignment: .leading, spacing: 0) {
                    Text(q.text)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(AQ.ink)
                        .padding(.horizontal, 24)
                        .padding(.top, 28)
                        .padding(.bottom, 6)

                    Text(q.quoteImpact)
                        .font(.system(size: 13))
                        .foregroundColor(AQ.blue)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)

                    ZStack(alignment: .topLeading) {
                        let binding = Binding(
                            get: { answers[q.id, default: ""] },
                            set: { answers[q.id] = $0 }
                        )
                        if answers[q.id, default: ""].isEmpty {
                            Text(q.hint)
                                .font(.system(size: 15))
                                .foregroundColor(AQ.secondary.opacity(0.6))
                                .padding(16)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: binding)
                            .font(.system(size: 15))
                            .foregroundColor(AQ.ink)
                            .focused($focused)
                            .frame(minHeight: 100)
                            .padding(12)
                            .scrollContentBackground(.hidden)
                    }
                    .background(AQ.fill)
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .stroke(focused ? AQ.blue : AQ.rule, lineWidth: 1))
                    .padding(.horizontal, 24)
                    .onAppear { focused = true }
                }

                Spacer()

                VStack(spacing: 8) {
                    Divider().background(AQ.rule).padding(.bottom, 8)
                    Button {
                        let ans = answers[q.id, default: ""].trimmingCharacters(in: .whitespaces)
                        if !ans.isEmpty {
                            engine.submitAnswer(ans)
                        }
                        if currentIdx < unanswered.count - 1 {
                            withAnimation { currentIdx += 1 }
                            answers[unanswered[currentIdx].id] = ""
                            focused = true
                        } else {
                            onContinue()
                        }
                    } label: {
                        Text(currentIdx < unanswered.count - 1 ? "Next" : "Generate Quote →")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(AQ.blue)
                            .cornerRadius(14)
                    }
                    .padding(.horizontal, 24)

                    Button("Skip and generate anyway") {
                        onContinue()
                    }
                    .font(.system(size: 13))
                    .foregroundColor(AQ.secondary)
                    .padding(.bottom, 28)
                }
            } else {
                // All done — should not render, but handle gracefully
                Spacer()
                Button("Continue") { onContinue() }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AQ.blue)
                    .cornerRadius(14)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 36)
            }
        }
    }
}

// MARK: - Voice Recorder

import Speech
import AVFoundation

@MainActor
final class VoiceRecorder: ObservableObject {
    @Published var isRecording = false
    @Published var transcript  = ""
    @Published var amplitude: [CGFloat] = Array(repeating: 0.12, count: 40)
    @Published var permissionDenied = false

    private var audioEngine      = AVAudioEngine()
    private var recognitionTask:   SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-GB"))
    private var amplitudeTimer: Timer?

    func toggle() {
        isRecording ? stop() : start()
    }

    private func start() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard status == .authorized else {
                    self.permissionDenied = true
                    return
                }
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        guard granted else { self.permissionDenied = true; return }
                        self.beginRecording()
                    }
                }
            }
        }
    }

    private func beginRecording() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? session.setActive(true, options: .notifyOthersOnDeactivation)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        recognitionTask = recognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.transcript = result.bestTranscription.formattedString
            }
            if error != nil || (result?.isFinal == true) {
                self.stop()
            }
        }

        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            // Derive amplitude from buffer for waveform
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameCount = Int(buffer.frameLength)
            let bufPtr = UnsafeBufferPointer(start: channelData, count: frameCount)
            let rms = sqrt(bufPtr.reduce(Float(0)) { $0 + $1 * $1 } / Float(frameCount))
            let db = CGFloat(max(0.05, min(1.0, Double(rms) * 12)))
            DispatchQueue.main.async {
                self?.pushAmplitude(db)
            }
        }

        try? audioEngine.start()
        isRecording = true

        // Animate idle waveform when no audio
        amplitudeTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            guard let self, self.isRecording else { return }
            Task { @MainActor in
                if self.amplitude.allSatisfy({ $0 < 0.15 }) {
                    self.pushAmplitude(CGFloat.random(in: 0.05...0.18))
                }
            }
        }
    }

    private func pushAmplitude(_ v: CGFloat) {
        amplitude.removeFirst()
        amplitude.append(v)
    }

    func stop() {
        amplitudeTimer?.invalidate(); amplitudeTimer = nil
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false)
        // Fade amplitude back to rest
        Task { @MainActor in
            withAnimation(.easeOut(duration: 0.4)) {
                amplitude = Array(repeating: 0.12, count: 40)
            }
        }
    }
}

// MARK: - Voice Input Card

struct VoiceInputCard: View {
    @ObservedObject var recorder: VoiceRecorder
    @Binding var transcript: String
    @State private var pulseRing = false

    var body: some View {
        VStack(spacing: 20) {

            // Waveform
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<recorder.amplitude.count, id: \.self) { i in
                    Capsule()
                        .fill(recorder.isRecording ? AQ.blue : AQ.rule)
                        .frame(width: 3, height: max(4, recorder.amplitude[i] * 48))
                        .animation(.easeOut(duration: 0.08), value: recorder.amplitude[i])
                }
            }
            .frame(height: 56)
            .padding(.horizontal, 4)

            // Transcript or prompt
            if transcript.isEmpty {
                Text(recorder.isRecording
                     ? "Listening…"
                     : "Tap the mic and describe the job")
                    .font(.system(size: 14))
                    .foregroundColor(AQ.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text(transcript)
                    .font(.system(size: 15))
                    .foregroundColor(AQ.ink)
                    .lineSpacing(4)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            // Mic button
            ZStack {
                // Pulse ring — only while recording
                if recorder.isRecording {
                    Circle()
                        .stroke(AQ.blue.opacity(0.2), lineWidth: 2)
                        .frame(width: 84, height: 84)
                        .scaleEffect(pulseRing ? 1.22 : 1.0)
                        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                                   value: pulseRing)
                        .onAppear { pulseRing = true }
                        .onDisappear { pulseRing = false }
                }

                Button { recorder.toggle() } label: {
                    ZStack {
                        Circle()
                            .fill(recorder.isRecording ? AQ.blue : AQ.fill)
                            .frame(width: 64, height: 64)
                            .shadow(color: recorder.isRecording ? AQ.blue.opacity(0.3) : .clear,
                                    radius: 12, x: 0, y: 4)
                            .animation(.easeInOut(duration: 0.2), value: recorder.isRecording)
                        Image(systemName: recorder.isRecording ? "stop.fill" : "mic")
                            .font(.system(size: recorder.isRecording ? 18 : 22, weight: .medium))
                            .foregroundColor(recorder.isRecording ? .white : AQ.ink)
                            .animation(.easeInOut(duration: 0.15), value: recorder.isRecording)
                    }
                }
            }
            .frame(height: 84)

            if recorder.permissionDenied {
                Text("Microphone access denied. Enable in Settings → AccuQuote Scan → Microphone.")
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 0.85, green: 0.35, blue: 0.2))
                    .multilineTextAlignment(.center)
            }

            if !transcript.isEmpty && !recorder.isRecording {
                Button {
                    transcript = ""
                    recorder.transcript = ""
                } label: {
                    Text("Clear and re-record")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AQ.secondary)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .stroke(recorder.isRecording ? AQ.blue.opacity(0.4) : AQ.rule, lineWidth: 1)
                .animation(.easeInOut(duration: 0.2), value: recorder.isRecording)
        )
    }
}

// MARK: - Quote Line Item model

struct QuoteLineItem: Identifiable, Codable {
    let id: UUID
    let description: String
    let qty: Double
    let unit: String
    let unitPrice: Double
    let sku: String
    let supplier: String
    let sectionKey: String   // which section this item belongs to
    var total: Double { qty * unitPrice }

    init(description: String, qty: Double, unit: String, unitPrice: Double,
         sku: String, supplier: String, sectionKey: String = "") {
        self.id = UUID()
        self.description = description
        self.qty = qty
        self.unit = unit
        self.unitPrice = unitPrice
        self.sku = sku
        self.supplier = supplier
        self.sectionKey = sectionKey
    }
}

struct GeneratedQuote {
    let sections: [QuoteSection]
    let vatRate: Double
    let customerName: String
    let jobDescription: String

    // Flat computed props — existing call sites continue to work unchanged
    var items: [QuoteLineItem] { sections.flatMap { $0.items } }
    var labourDays: Double { sections.reduce(0) { $0 + $1.labourDays } }
    var labourRate: Double { sections.first(where: { $0.labourDays > 0 })?.labourRate ?? 280 }
    var labourTotal: Double { sections.reduce(0) { $0 + $1.labourTotal } }
    var materialsTotal: Double { sections.reduce(0) { $0 + $1.materialsTotal } }
    var subtotal: Double { labourTotal + materialsTotal }
    var vatAmount: Double { subtotal * (vatRate / 100) }
    var grandTotal: Double { subtotal + vatAmount }
    var notes: String { sections.compactMap { $0.notes.isEmpty ? nil : $0.notes }.joined(separator: "\n") }
}

// MARK: - Quote View

struct QuoteView: View {
    let result: RoomDimensions
    let jobDescription: String
    let customerName: String
    @ObservedObject var coordinator: ScanCoordinator
    @EnvironmentObject var questionEngine: QuestionEngine
    @Environment(\.dismiss) var dismiss

    @StateObject private var service = QuoteGenerationService()

    private var preferredSupplier: String {
        let ans = questionEngine.profile.answers.first(where: { $0.id == "supplier" })?.answer ?? ""
        return ans.isEmpty ? "Screwfix or Toolstation" : ans
    }

    var body: some View {
        NavigationView {
            Group {
                switch service.state {
                case .idle, .discoveringSections:
                    QuoteLoadingView(
                        step: 0,
                        steps: ["Planning your quote…", "Identifying trade sections…"]
                    )
                case .generatingSections(let total, let completed):
                    SectionedQuoteLoadingView(service: service, total: total, completed: completed)
                case .complete:
                    let quote = GeneratedQuote(
                        sections: service.sections,
                        vatRate: service.vatRate,
                        customerName: customerName,
                        jobDescription: jobDescription
                    )
                    QuoteResultView(quote: quote, result: result) {
                        dismiss(); coordinator.reset()
                    }
                case .failed(let message):
                    QuoteErrorView(message: message) {
                        startGeneration()
                    }
                }
            }
            .navigationTitle("Quote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if case .complete = service.state {
                        Button("Back") { dismiss() }.foregroundColor(AQ.secondary)
                    }
                }
            }
        }
        .onAppear { startGeneration() }
    }

    private func startGeneration() {
        let ctx = questionEngine.claudeContext()
        let supplier = preferredSupplier
        let usualItems = questionEngine.profile.answers
            .first(where: { $0.id == "usual_items" })?.answer ?? ""
        let dims = result
        let job  = jobDescription
        let cust = customerName
        Task.detached(priority: .userInitiated) {
            await service.generate(
                jobDescription: job,
                customerName: cust,
                roomDimensions: dims,
                claudeContext: ctx,
                preferredSupplier: supplier,
                usualItems: usualItems
            )
        }
    }

}

// MARK: - Quote Loading View

struct QuoteLoadingView: View {
    let step: Int
    let steps: [String]
    @State private var pulse = false
    @State private var orbRotate = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Orb
            ZStack {
                Circle().fill(AQ.blue.opacity(0.06)).frame(width: 110, height: 110)
                    .scaleEffect(pulse ? 1.18 : 1.0)
                    .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: pulse)
                Circle().fill(AQ.blue.opacity(0.11)).frame(width: 78, height: 78)
                // Spinning arc
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(AQ.blue.opacity(0.45), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(orbRotate ? 360 : 0))
                    .animation(.linear(duration: 1.8).repeatForever(autoreverses: false), value: orbRotate)
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .light))
                    .foregroundColor(AQ.blue)
            }
            .onAppear { pulse = true; orbRotate = true }
            .padding(.bottom, 32)

            Text("Building your quote")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(AQ.ink)
                .padding(.bottom, 6)

            Text("Pricing live from your supplier catalogue")
                .font(.system(size: 13))
                .foregroundColor(AQ.secondary)
                .padding(.bottom, 36)

            // Step checklist
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, label in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(i < step ? AQ.green : (i == step ? AQ.blue.opacity(0.12) : AQ.fill))
                                .frame(width: 22, height: 22)
                            if i < step {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                            } else if i == step {
                                ProgressView()
                                    .scaleEffect(0.5)
                                    .tint(AQ.blue)
                                    .frame(width: 22, height: 22)
                            } else {
                                Circle()
                                    .fill(AQ.secondary.opacity(0.2))
                                    .frame(width: 7, height: 7)
                            }
                        }
                        Text(label)
                            .font(.system(size: 14, weight: i <= step ? .medium : .regular))
                            .foregroundColor(i < step ? AQ.green : (i == step ? AQ.ink : AQ.secondary.opacity(0.5)))
                            .animation(.easeInOut(duration: 0.25), value: step)
                    }
                }
            }
            .padding(.horizontal, 48)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }
}

// MARK: - Sectioned Quote Loading View

struct SectionedQuoteLoadingView: View {
    @ObservedObject var service: QuoteGenerationService
    let total: Int
    let completed: Int

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        ProgressView()
                            .scaleEffect(0.85)
                        Text("\(completed) of \(total) sections")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AQ.secondary)
                        Spacer()
                        if service.grandTotal > 0 {
                            Text("£\(Int(service.grandTotal).formatted())")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundColor(AQ.ink)
                                .contentTransition(.numericText())
                                .animation(.easeInOut(duration: 0.3), value: service.grandTotal)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)

                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(AQ.rule).frame(height: 3)
                            Rectangle()
                                .fill(AQ.blue)
                                .frame(width: geo.size.width * CGFloat(completed) / CGFloat(max(total, 1)), height: 3)
                                .animation(.easeInOut(duration: 0.4), value: completed)
                        }
                    }
                    .frame(height: 3)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                }

                // Section cards
                LazyVStack(spacing: 0) {
                    ForEach(service.sections) { section in
                        SectionStatusCard(section: section)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: service.sections.count)
            }
        }
        .background(Color.white)
    }
}

private struct SectionStatusCard: View {
    let section: QuoteSection

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Status icon
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.1))
                        .frame(width: 32, height: 32)
                    statusIcon
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(statusColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(section.label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AQ.ink)
                    if case .complete = section.status {
                        Text("\(section.items.count) items · £\(Int(section.sectionSubtotal).formatted())")
                            .font(.system(size: 12))
                            .foregroundColor(AQ.secondary)
                    } else if case .loading = section.status {
                        Text("Pricing items…")
                            .font(.system(size: 12))
                            .foregroundColor(AQ.secondary)
                    } else if case .failed(let reason) = section.status {
                        Text(reason)
                            .font(.system(size: 12))
                            .foregroundColor(.red.opacity(0.7))
                            .lineLimit(1)
                    } else {
                        Text("Waiting…")
                            .font(.system(size: 12))
                            .foregroundColor(AQ.secondary)
                    }
                }
                Spacer()
                if case .complete = section.status {
                    Text("£\(Int(section.sectionSubtotal).formatted())")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(AQ.ink)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            Divider().background(AQ.rule).padding(.leading, 24)
        }
    }

    private var statusColor: Color {
        switch section.status {
        case .complete:      return AQ.green
        case .loading:       return AQ.blue
        case .failed:        return .red
        case .pending:       return AQ.secondary
        }
    }

    private var statusIcon: Image {
        switch section.status {
        case .complete:      return Image(systemName: "checkmark")
        case .loading:       return Image(systemName: "arrow.triangle.2.circlepath")
        case .failed:        return Image(systemName: "exclamationmark")
        case .pending:       return Image(systemName: "clock")
        }
    }
}

// MARK: - Quote Error View

struct QuoteErrorView: View {
    let message: String
    let onRetry: () -> Void
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 44, weight: .light))
                .foregroundColor(AQ.secondary)
            Text("Quote Failed")
                .font(.system(size: 22, weight: .semibold)).foregroundColor(AQ.ink)
            Text(message)
                .font(AQ.body(15)).foregroundColor(AQ.secondary)
                .multilineTextAlignment(.center).lineSpacing(4).padding(.horizontal, 40)
            Spacer()
            VStack(spacing: 0) {
                Divider().background(AQ.rule).padding(.bottom, 20)
                Button(action: onRetry) {
                    Text("Try Again")
                        .font(.system(size: 17, weight: .semibold)).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 17)
                        .background(AQ.blue).cornerRadius(14)
                }
                .padding(.horizontal, 24).padding(.bottom, 36)
            }
        }
        .background(Color.white)
    }
}

// MARK: - Quote Result View

struct QuoteResultView: View {
    let quote: GeneratedQuote
    let result: RoomDimensions
    let onStartOver: () -> Void
    @EnvironmentObject var questionEngine: QuestionEngine
    @State private var pdfURL: URL?
    @State private var showBreakdown = false
    @State private var editingLabourTotal = false
    @State private var labourTotalOverride: Double? = nil
    @State private var showProfileNudge = true
    @State private var showOnboarding = false
    @State private var showDepositSheet = false

    var effectiveLabourTotal: Double { labourTotalOverride ?? quote.labourTotal }
    var effectiveSubtotal: Double { effectiveLabourTotal + quote.items.reduce(0) { $0 + $1.total } }
    var effectiveVatAmount: Double { effectiveSubtotal * (quote.vatRate / 100) }
    var effectiveGrandTotal: Double { effectiveSubtotal + effectiveVatAmount }

    private var profileNudgeQuestion: OnboardingQuestion? {
        guard questionEngine.answeredCount < 6 else { return nil }
        let priority = ["day_rate", "trade", "region", "material_markup", "vat"]
        return priority.compactMap { id in
            questionEngine.questions.first(where: { $0.id == id && !$0.isAnswered })
        }.first
    }

    var body: some View {
        VStack(spacing: 0) {
        ScrollView {
            VStack(spacing: 0) {

                // Grand total hero
                VStack(spacing: 6) {
                    Text("Total")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AQ.secondary)
                        .kerning(0.8)
                        .textCase(.uppercase)
                    Text("£\(Int(effectiveGrandTotal).formatted())")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundColor(AQ.ink)
                    Text("inc. VAT")
                        .font(AQ.body(13))
                        .foregroundColor(AQ.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .background(AQ.fill)

                Divider().background(AQ.rule)

                // Profile nudge banner
                if showProfileNudge, let q = profileNudgeQuestion {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Make this quote more accurate")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AQ.ink)
                            Text(q.text)
                                .font(.system(size: 12))
                                .foregroundColor(AQ.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button("Answer") {
                            showProfileNudge = false
                            showOnboarding = true
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(AQ.blue).cornerRadius(8)
                        Button { showProfileNudge = false } label: {
                            Image(systemName: "xmark").font(.system(size: 10)).foregroundColor(AQ.secondary)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(AQ.blue.opacity(0.06))
                    .overlay(Rectangle().frame(height: 1).foregroundColor(AQ.blue.opacity(0.12)), alignment: .bottom)
                }

                // Summary rows always visible
                QuoteSectionHeader(title: "Summary")
                Button {
                    labourTotalOverride = labourTotalOverride ?? quote.labourTotal
                    editingLabourTotal = true
                } label: {
                    QuoteRow(label: "Labour ✎", value: "£\(Int(effectiveLabourTotal).formatted())", bold: false)
                }
                Divider().background(AQ.rule).padding(.leading, 24)
                if !quote.items.isEmpty {
                    QuoteRow(label: "Materials", value: "£\(Int(quote.items.reduce(0) { $0 + $1.total }).formatted())", bold: false)
                    Divider().background(AQ.rule).padding(.leading, 24)
                }
                QuoteRow(label: "VAT (\(Int(quote.vatRate))%)", value: "£\(String(format: "%.2f", effectiveVatAmount))", bold: false)
                Divider().background(AQ.rule).padding(.leading, 24)
                QuoteRow(label: "Total", value: "£\(Int(effectiveGrandTotal).formatted())", bold: true)
                Divider().background(AQ.rule)

                // Breakdown toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) { showBreakdown.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Text(showBreakdown ? "Hide breakdown" : "View breakdown")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AQ.blue)
                        Image(systemName: showBreakdown ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AQ.blue)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }

                if showBreakdown {
                    Divider().background(AQ.rule)

                    if quote.sections.count > 1 {
                        // ── Multi-section breakdown ──────────────────────────
                        ForEach(quote.sections) { section in
                            QuoteSectionHeader(title: section.label)
                            // Labour row for this section
                            if section.labourDays > 0 {
                                QuoteRow(
                                    label: "\(String(format: "%.1f", section.labourDays))d labour @ £\(Int(section.labourRate))/day",
                                    value: "£\(Int(section.labourTotal).formatted())",
                                    bold: false
                                )
                                Divider().background(AQ.rule).padding(.leading, 24)
                            }
                            ForEach(section.items) { item in
                                QuoteLineItemRow(item: item, formatQty: formatQty)
                            }
                            if !section.notes.isEmpty {
                                Text(section.notes)
                                    .font(AQ.body(13)).foregroundColor(AQ.secondary)
                                    .lineSpacing(4)
                                    .padding(.horizontal, 24).padding(.vertical, 10)
                                Divider().background(AQ.rule).padding(.leading, 24)
                            }
                            QuoteRow(
                                label: "Section subtotal",
                                value: "£\(Int(section.sectionSubtotal).formatted())",
                                bold: true
                            )
                            Divider().background(AQ.rule)
                        }
                    } else {
                        // ── Single-section (legacy) breakdown ────────────────
                        QuoteSectionHeader(title: "Labour")
                        QuoteRow(
                            label: "\(String(format: "%.1f", quote.labourDays)) day\(quote.labourDays == 1 ? "" : "s") @ £\(Int(quote.labourRate))/day",
                            value: "£\(Int(effectiveLabourTotal).formatted())",
                            bold: false
                        )
                        Divider().background(AQ.rule).padding(.leading, 24)
                        if !quote.items.isEmpty {
                            QuoteSectionHeader(title: "Materials & Items")
                            ForEach(quote.items) { item in
                                QuoteLineItemRow(item: item, formatQty: formatQty)
                            }
                        }
                        if !quote.notes.isEmpty {
                            QuoteSectionHeader(title: "Notes & Inclusions")
                            Text(quote.notes)
                                .font(AQ.body(14)).foregroundColor(AQ.secondary)
                                .lineSpacing(5)
                                .padding(.horizontal, 24).padding(.vertical, 16)
                            Divider().background(AQ.rule)
                        }
                    }
                }

                Color.clear.frame(height: 20)
            }
        }
        .background(Color.white)

        // Sticky footer
        VStack(spacing: 0) {
            Divider().background(AQ.rule)

            // Row 1: New Quote + Send to customer
            HStack(spacing: 10) {
                Button(action: onStartOver) {
                    Text("New Quote")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(AQ.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(AQ.fill)
                        .cornerRadius(14)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AQ.rule, lineWidth: 1))
                }
                .frame(width: 110)

                Button {
                    pdfURL = buildPDF(summarised: true)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Send to customer")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AQ.blue)
                    .cornerRadius(14)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            // Row 2: Full BOM + Request deposit
            HStack(spacing: 10) {
                Button {
                    pdfURL = buildPDF(summarised: false)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Full BOM")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(AQ.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(AQ.fill)
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(AQ.rule, lineWidth: 1))
                }

                Button {
                    showDepositSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "creditcard")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Request deposit via Stripe")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(AQ.green)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(AQ.green.opacity(0.09))
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(AQ.green.opacity(0.25), lineWidth: 1))
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(Color.white)
        } // end outer VStack
        .background(Color.white)
        .sheet(item: $pdfURL) { url in
            ShareSheet(url: url)
        }
        .sheet(isPresented: $editingLabourTotal) {
            LabourEditSheet(
                current: effectiveLabourTotal,
                onSave: { newVal in
                    labourTotalOverride = newVal
                    editingLabourTotal = false
                },
                onCancel: { editingLabourTotal = false }
            )
            .presentationDetents([.height(260)])
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingSheet().environmentObject(questionEngine)
        }
        .sheet(isPresented: $showDepositSheet) {
            let traderName = questionEngine.profile.answers
                .first(where: { $0.id == "business_name" })?.answer ?? "AccuQuote"
            DepositRequestView(
                quote: quote,
                effectiveGrandTotal: effectiveGrandTotal,
                traderName: traderName,
                onDismiss: { showDepositSheet = false }
            )
        }
    }

    private func formatQty(_ qty: Double) -> String {
        qty == qty.rounded() ? "\(Int(qty))" : String(format: "%.1f", qty)
    }

    // MARK: - PDF Generation

    private func buildPDF(summarised: Bool = true, depositURL: String? = nil) -> URL {
        let profile = questionEngine.profile
        let businessName    = profile.answers.first(where: { $0.id == "business_name" })?.answer ?? "AccuQuote"
        let businessContact = profile.answers.first(where: { $0.id == "business_contact" })?.answer ?? ""
        let traderName      = profile.answers.first(where: { $0.id == "trade" })?.answer ?? ""
        let region          = profile.answers.first(where: { $0.id == "region" })?.answer ?? ""

        let pageW: CGFloat = 595   // A4 points
        let pageH: CGFloat = 842
        let margin: CGFloat = 48
        let col2: CGFloat = pageW - margin   // right edge

        let fmt = UIGraphicsPDFRendererFormat()
        fmt.documentInfo = [
            kCGPDFContextTitle as String:  "Quote — \(businessName)",
            kCGPDFContextAuthor as String: businessName,
        ]

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageW, height: pageH), format: fmt)

        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AccuQuote-\(UUID().uuidString.prefix(8)).pdf")

        let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .none)

        try? renderer.writePDF(to: tmpURL) { ctx in
            ctx.beginPage()
            var y: CGFloat = margin

            // ── Header bar ──────────────────────────────────────────────────
            let headerRect = CGRect(x: 0, y: 0, width: pageW, height: 80)
            UIColor(AQ.ink).setFill(); UIRectFill(headerRect)

            let bizAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 18, weight: .bold),
                .foregroundColor: UIColor.white,
            ]
            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11),
                .foregroundColor: UIColor.white.withAlphaComponent(0.65),
            ]
            businessName.draw(at: CGPoint(x: margin, y: 20), withAttributes: bizAttrs)
            let subLine = [traderName, region].filter { !$0.isEmpty }.joined(separator: " · ")
            if !subLine.isEmpty {
                subLine.draw(at: CGPoint(x: margin, y: 43), withAttributes: subAttrs)
            }
            if !businessContact.isEmpty {
                businessContact.draw(at: CGPoint(x: margin, y: 57), withAttributes: subAttrs)
            }
            // Date right-aligned
            let dateAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11),
                .foregroundColor: UIColor.white.withAlphaComponent(0.65),
            ]
            let dateSize = dateStr.size(withAttributes: dateAttrs)
            dateStr.draw(at: CGPoint(x: col2 - dateSize.width, y: 57), withAttributes: dateAttrs)

            y = 100

            // ── QUOTE title + total ──────────────────────────────────────────
            let quoteLabel = "QUOTE"
            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: UIColor(AQ.secondary),
                .kern: 2.0,
            ]
            quoteLabel.draw(at: CGPoint(x: margin, y: y), withAttributes: labelAttrs)
            y += 18

            // Customer
            if !quote.customerName.isEmpty {
                let custAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
                    .foregroundColor: UIColor(AQ.ink),
                ]
                quote.customerName.draw(at: CGPoint(x: margin, y: y), withAttributes: custAttrs)
                y += 22
            }

            // Grand total right block
            let totalStr = "£\(Int(quote.grandTotal).formatted())"
            let totalAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 36, weight: .bold),
                .foregroundColor: UIColor(AQ.ink),
            ]
            let totalSize = totalStr.size(withAttributes: totalAttrs)
            totalStr.draw(at: CGPoint(x: col2 - totalSize.width, y: y - 10), withAttributes: totalAttrs)
            let incVATAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10),
                .foregroundColor: UIColor(AQ.secondary),
            ]
            "inc. VAT".draw(at: CGPoint(x: col2 - 42, y: y + 30), withAttributes: incVATAttrs)

            y += 52

            // ── Divider ──────────────────────────────────────────────────────
            func drawRule(_ yPos: CGFloat) {
                UIColor(AQ.rule).setStroke()
                let path = UIBezierPath()
                path.move(to: CGPoint(x: margin, y: yPos))
                path.addLine(to: CGPoint(x: col2, y: yPos))
                path.lineWidth = 0.5; path.stroke()
            }
            drawRule(y); y += 16

            // ── Section header helper ────────────────────────────────────────
            func sectionHeader(_ title: String) {
                let a: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 9, weight: .semibold),
                    .foregroundColor: UIColor(AQ.secondary),
                    .kern: 1.2,
                ]
                title.uppercased().draw(at: CGPoint(x: margin, y: y), withAttributes: a)
                y += 16
            }

            // ── Row helper ───────────────────────────────────────────────────
            func row(left: String, right: String, bold: Bool = false, secondary: String = "") {
                let lAttrs: [NSAttributedString.Key: Any] = [
                    .font: bold ? UIFont.systemFont(ofSize: 13, weight: .semibold)
                                : UIFont.systemFont(ofSize: 13),
                    .foregroundColor: UIColor(AQ.ink),
                ]
                let rAttrs: [NSAttributedString.Key: Any] = [
                    .font: bold ? UIFont.systemFont(ofSize: 13, weight: .semibold)
                                : UIFont.systemFont(ofSize: 13),
                    .foregroundColor: UIColor(bold ? AQ.ink : AQ.ink),
                ]
                left.draw(at: CGPoint(x: margin, y: y), withAttributes: lAttrs)
                let rSize = right.size(withAttributes: rAttrs)
                right.draw(at: CGPoint(x: col2 - rSize.width, y: y), withAttributes: rAttrs)
                y += 18
                if !secondary.isEmpty {
                    let sAttrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 10),
                        .foregroundColor: UIColor(AQ.secondary),
                    ]
                    secondary.draw(at: CGPoint(x: margin, y: y), withAttributes: sAttrs)
                    y += 14
                }
                y += 4
                drawRule(y); y += 10
            }

            // ── Labour ───────────────────────────────────────────────────────
            sectionHeader("Labour")
            let labourLabel = "\(String(format: "%.1f", quote.labourDays)) day\(quote.labourDays == 1 ? "" : "s") @ £\(Int(quote.labourRate))/day"
            row(left: labourLabel, right: "£\(Int(quote.labourTotal).formatted())")

            // ── Materials ────────────────────────────────────────────────────
            if !quote.items.isEmpty {
                y += 6
                if summarised {
                    // Customer quote: single materials total, no SKUs or supplier names
                    sectionHeader("Materials")
                    let matTotal = quote.items.reduce(0) { $0 + $1.total }
                    row(left: "Materials & supplies", right: "£\(Int(matTotal).formatted())")
                } else {
                    // Full BOM: every line item with SKU and supplier
                    sectionHeader("Materials & Items")
                    for item in quote.items {
                        var meta = "\(formatQty(item.qty)) \(item.unit) × £\(String(format: "%.2f", item.unitPrice))"
                        if !item.sku.isEmpty {
                            let sup = item.supplier.isEmpty ? "" : "\(item.supplier) "
                            meta += "   \(sup)SKU \(item.sku)"
                        }
                        let maxDescWidth = pageW - margin * 2 - 80
                        let descAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 13)]
                        let descWidth = item.description.size(withAttributes: descAttrs).width
                        if descWidth > maxDescWidth {
                            row(left: String(item.description.prefix(55)) + "…",
                                right: "£\(String(format: "%.2f", item.total))",
                                secondary: meta)
                        } else {
                            row(left: item.description,
                                right: "£\(String(format: "%.2f", item.total))",
                                secondary: meta)
                        }
                    }
                }
            }

            // ── Summary ──────────────────────────────────────────────────────
            y += 6
            sectionHeader("Summary")
            row(left: "Subtotal",               right: "£\(Int(quote.subtotal).formatted())")
            row(left: "VAT (\(Int(quote.vatRate))%)", right: "£\(String(format: "%.2f", quote.vatAmount))")
            row(left: "Total",                  right: "£\(Int(quote.grandTotal).formatted())", bold: true)

            // ── Notes ────────────────────────────────────────────────────────
            if !quote.notes.isEmpty {
                y += 10
                sectionHeader("Notes & Inclusions")
                let notesAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 12),
                    .foregroundColor: UIColor(AQ.secondary),
                ]
                let maxW = pageW - margin * 2
                let notesRect = CGRect(x: margin, y: y, width: maxW, height: 200)
                quote.notes.draw(in: notesRect, withAttributes: notesAttrs)
                let estimatedLines = max(1, Int(ceil(Double(quote.notes.count) / 90)))
                y += CGFloat(estimatedLines) * 16 + 16
            }

            // ── Job description ──────────────────────────────────────────────
            y += 6
            sectionHeader("Job Description")
            let jobAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor(AQ.secondary),
            ]
            let jobRect = CGRect(x: margin, y: y, width: pageW - margin * 2, height: 150)
            quote.jobDescription.draw(in: jobRect, withAttributes: jobAttrs)

            // ── Footer ───────────────────────────────────────────────────────
            let footerY: CGFloat = pageH - 36
            drawRule(footerY - 8)
            let footerAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9),
                .foregroundColor: UIColor(AQ.secondary),
            ]
            "Generated by AccuQuote".draw(at: CGPoint(x: margin, y: footerY), withAttributes: footerAttrs)
            let footerDate = "Quote date: \(dateStr)"
            let fdSize = footerDate.size(withAttributes: footerAttrs)
            footerDate.draw(at: CGPoint(x: col2 - fdSize.width, y: footerY), withAttributes: footerAttrs)
        }

        return tmpURL
    }
}


// MARK: - Deposit Request View

struct DepositRequestView: View {
    let quote: GeneratedQuote
    let effectiveGrandTotal: Double
    let traderName: String
    let onDismiss: () -> Void

    @State private var selectedPreset: Int? = 25       // % preset button selected
    @State private var customInput: String = ""
    @State private var useCustom = false
    @State private var isLoading = false
    @State private var paymentLink: DepositPaymentLink? = nil
    @State private var errorMessage: String? = nil
    @State private var showShareSheet = false
    @State private var shareURL: URL? = nil

    private let presets = [10, 25, 50]

    private var depositAmount: Double {
        if useCustom {
            return Double(customInput.filter { $0.isNumber || $0 == "." }) ?? 0
        }
        let pct = Double(selectedPreset ?? 25) / 100.0
        return (effectiveGrandTotal * pct * 100).rounded() / 100
    }

    private var serviceFeeAmount: Double {
        (depositAmount * 0.01 * 100).rounded() / 100
    }

    private var isValidAmount: Bool {
        depositAmount > 0.50 && depositAmount <= effectiveGrandTotal
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {

                    // ── Header ────────────────────────────────────────────
                    VStack(spacing: 4) {
                        Text("Request a Deposit")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(AQ.ink)
                        Text("Send a Stripe payment link with your quote")
                            .font(AQ.body(14))
                            .foregroundColor(AQ.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 28)
                    .padding(.bottom, 24)
                    .padding(.horizontal, 24)

                    Divider().background(AQ.rule)

                    // ── Quote total context ───────────────────────────────
                    HStack {
                        Text("Quote total")
                            .font(AQ.body(15))
                            .foregroundColor(AQ.secondary)
                        Spacer()
                        Text("£\(Int(effectiveGrandTotal).formatted())")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AQ.ink)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)

                    Divider().background(AQ.rule)

                    // ── Preset buttons ────────────────────────────────────
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Deposit amount")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AQ.secondary)
                            .textCase(.uppercase)
                            .kerning(0.6)
                            .padding(.horizontal, 24)

                        HStack(spacing: 10) {
                            ForEach(presets, id: \.self) { pct in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        selectedPreset = pct
                                        useCustom = false
                                        customInput = ""
                                    }
                                } label: {
                                    VStack(spacing: 3) {
                                        Text("\(pct)%")
                                            .font(.system(size: 16, weight: .semibold))
                                        Text("£\(Int((effectiveGrandTotal * Double(pct) / 100).rounded()).formatted())")
                                            .font(.system(size: 12))
                                    }
                                    .foregroundColor((!useCustom && selectedPreset == pct) ? .white : AQ.ink)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background((!useCustom && selectedPreset == pct) ? AQ.blue : AQ.fill)
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke((!useCustom && selectedPreset == pct) ? AQ.blue : AQ.rule, lineWidth: 1)
                                    )
                                }
                            }

                            // Custom button
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    useCustom = true
                                    selectedPreset = nil
                                }
                            } label: {
                                Text(useCustom ? "Custom ✎" : "Custom")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(useCustom ? .white : AQ.ink)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(useCustom ? AQ.blue : AQ.fill)
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(useCustom ? AQ.blue : AQ.rule, lineWidth: 1)
                                    )
                            }
                        }
                        .padding(.horizontal, 24)

                        if useCustom {
                            HStack {
                                Text("£")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundColor(AQ.secondary)
                                TextField("e.g. 500", text: $customInput)
                                    .keyboardType(.decimalPad)
                                    .font(.system(size: 17))
                                    .foregroundColor(AQ.ink)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(AQ.fill)
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AQ.blue, lineWidth: 1.5))
                            .padding(.horizontal, 24)
                        }
                    }
                    .padding(.vertical, 20)

                    Divider().background(AQ.rule)

                    // ── Fee breakdown ─────────────────────────────────────
                    VStack(spacing: 0) {
                        HStack {
                            Text("Customer pays")
                                .font(AQ.body(15))
                                .foregroundColor(AQ.secondary)
                            Spacer()
                            Text(isValidAmount ? "£\(String(format: "%.2f", depositAmount))" : "—")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(AQ.ink)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)

                        Divider().background(AQ.rule).padding(.leading, 24)

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("AccuQuote service fee")
                                    .font(AQ.body(15))
                                    .foregroundColor(AQ.secondary)
                                Text("1% of deposit — deducted from payout")
                                    .font(AQ.body(12))
                                    .foregroundColor(AQ.secondary.opacity(0.7))
                            }
                            Spacer()
                            Text(isValidAmount ? "£\(String(format: "%.2f", serviceFeeAmount))" : "—")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(AQ.secondary)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)

                        Divider().background(AQ.rule).padding(.leading, 24)

                        HStack {
                            Text("You receive")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(AQ.ink)
                            Spacer()
                            Text(isValidAmount ? "£\(String(format: "%.2f", depositAmount - serviceFeeAmount))" : "—")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(AQ.green)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                    }

                    Divider().background(AQ.rule)

                    // ── Error message ─────────────────────────────────────
                    if let error = errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .font(AQ.body(14))
                                .foregroundColor(.red)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.06))
                        .cornerRadius(10)
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                    }

                    // ── Success — show link ───────────────────────────────
                    if let link = paymentLink {
                        VStack(spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(AQ.green)
                                    .font(.system(size: 18))
                                Text("Payment link created")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(AQ.green)
                            }

                            Text(link.url.absoluteString)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(AQ.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)

                            Button {
                                shareURL = link.url
                                showShareSheet = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 15, weight: .semibold))
                                    Text("Share payment link")
                                        .font(.system(size: 17, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(AQ.green)
                                .cornerRadius(14)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                    }

                    Color.clear.frame(height: 100)
                }
            }
            .background(Color.white)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { onDismiss() }
                        .foregroundColor(AQ.secondary)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if paymentLink == nil {
                    VStack(spacing: 0) {
                        Divider().background(AQ.rule)
                        Button {
                            Task { await generateLink() }
                        } label: {
                            Group {
                                if isLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    HStack(spacing: 8) {
                                        Image(systemName: "link")
                                            .font(.system(size: 15, weight: .semibold))
                                        Text("Create payment link")
                                            .font(.system(size: 17, weight: .semibold))
                                    }
                                }
                            }
                            .foregroundColor(isValidAmount ? .white : AQ.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(isValidAmount ? AQ.blue : AQ.fill)
                            .cornerRadius(14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(isValidAmount ? Color.clear : AQ.rule, lineWidth: 1)
                            )
                        }
                        .disabled(!isValidAmount || isLoading)
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                        .padding(.bottom, 28)
                    }
                    .background(Color.white)
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = shareURL {
                ShareSheet(url: url)
            }
        }
    }

    @MainActor
    private func generateLink() async {
        errorMessage = nil
        isLoading = true
        do {
            let link = try await StripeService.createPaymentLink(
                depositAmount:  depositAmount,
                customerName:   quote.customerName,
                jobDescription: quote.jobDescription,
                traderName:     traderName
            )
            paymentLink = link
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - PDF Share Sheet

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Quote row components

struct QuoteLineItemRow: View {
    let item: QuoteLineItem
    let formatQty: (Double) -> String
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            QuoteRow(
                label: item.description,
                value: "£\(String(format: "%.2f", item.total))",
                bold: false, multiline: false
            )
            HStack(spacing: 8) {
                Text("\(formatQty(item.qty)) \(item.unit) × £\(String(format: "%.2f", item.unitPrice))")
                    .font(.system(size: 12)).foregroundColor(AQ.secondary)
                if !item.sku.isEmpty {
                    Text("·").foregroundColor(AQ.rule)
                    HStack(spacing: 3) {
                        if !item.supplier.isEmpty {
                            Text(item.supplier)
                                .font(.system(size: 11, weight: .medium)).foregroundColor(AQ.blue)
                        }
                        Text("SKU \(item.sku)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(AQ.blue)
                    }
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(AQ.blue.opacity(0.07)).cornerRadius(5)
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 12)
        }
        Divider().background(AQ.rule).padding(.leading, 24)
    }
}

struct QuoteSectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .kerning(0.8)
            .foregroundColor(AQ.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 4)
    }
}

struct QuoteRow: View {
    let label: String
    let value: String
    let bold: Bool
    var multiline: Bool = false

    var body: some View {
        HStack(alignment: multiline ? .top : .center) {
            Text(label)
                .font(bold ? .system(size: 15, weight: .semibold) : AQ.body(15))
                .foregroundColor(bold ? AQ.ink : AQ.label)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value)
                .font(bold ? .system(size: 17, weight: .bold) : .system(size: 15, weight: .medium))
                .foregroundColor(bold ? AQ.ink : AQ.label)
                .monospacedDigit()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
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

// MARK: - Labour Edit Sheet

private struct LabourEditSheet: View {
    let current: Double
    let onSave: (Double) -> Void
    let onCancel: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var parsed: Double? { Double(text.replacingOccurrences(of: "£", with: "").replacingOccurrences(of: ",", with: "")) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Edit Labour Total")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(AQ.ink)
            Text("Override the calculated labour cost for this quote.")
                .font(.system(size: 14))
                .foregroundColor(AQ.secondary)
            HStack {
                Text("£").font(.system(size: 22, weight: .semibold)).foregroundColor(AQ.secondary)
                TextField("0", text: $text)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(AQ.ink)
                    .keyboardType(.decimalPad)
                    .focused($focused)
            }
            .padding(16)
            .background(AQ.fill)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AQ.blue, lineWidth: 1.5))
            HStack(spacing: 10) {
                Button("Cancel") { onCancel() }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AQ.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(AQ.fill).cornerRadius(12)
                Button("Save") {
                    if let v = parsed { onSave(v) }
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(parsed != nil ? AQ.blue : AQ.rule).cornerRadius(12)
                .disabled(parsed == nil)
            }
        }
        .padding(28)
        .onAppear {
            text = String(Int(current))
            focused = true
        }
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

/// Bridges the RoomPlan LiDAR scan into SwiftUI via a UIViewController.
/// RoomPlan's RoomCaptureView must live inside a UIViewController — it won't
/// render correctly as a bare UIViewRepresentable in a SwiftUI hierarchy.
struct LiDARHostRepresentable: UIViewControllerRepresentable {
    let coordinator: ScanCoordinator

    func makeUIViewController(context: Context) -> LiDARHostVC {
        LiDARHostVC(scanCoordinator: coordinator)
    }

    func updateUIViewController(_ vc: LiDARHostVC, context: Context) {}
}

final class LiDARHostVC: UIViewController {
    private let scanCoordinator: ScanCoordinator
    private var captureView: RoomCaptureView?

    init(scanCoordinator: ScanCoordinator) {
        self.scanCoordinator = scanCoordinator
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        // RoomCaptureView MUST be the root view — Metal won't render as a subview.
        let captureView = RoomCaptureView(frame: UIScreen.main.bounds)
        self.captureView = captureView
        scanCoordinator.setCaptureView(captureView)
        view = captureView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addDoneButton()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scanCoordinator.beginLiDARSession()
    }

    private func addDoneButton() {
        let btn = UIButton(type: .system)
        btn.setTitle("Done", for: .normal)
        btn.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        btn.setTitleColor(.white, for: .normal)
        btn.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        btn.layer.cornerRadius = 18
        if #available(iOS 15, *) {
            var config = UIButton.Configuration.plain()
            config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 18)
            btn.configuration = config
            btn.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attr in
                var a = attr; a.font = UIFont.systemFont(ofSize: 15, weight: .semibold); return a
            }
        } else {
            btn.contentEdgeInsets = UIEdgeInsets(top: 8, left: 18, bottom: 8, right: 18)
        }
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        view.addSubview(btn)
        NSLayoutConstraint.activate([
            btn.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            btn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])
    }

    @objc private func doneTapped() {
        scanCoordinator.stopScan()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        captureView?.removeFromSuperview()
        captureView = nil
    }
}

// Wraps ARSCNView in a UIViewController so we can start the session in viewDidAppear,
// guaranteeing the Metal layer has a valid drawable before session.run() is called.
final class ARHostVC: UIViewController {
    private let scanCoordinator: ScanCoordinator
    private var sceneView: ARSCNView?

    init(scanCoordinator: ScanCoordinator) {
        self.scanCoordinator = scanCoordinator
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let v = ARSCNView(frame: UIScreen.main.bounds)
        v.automaticallyUpdatesLighting = true
        v.session = scanCoordinator.arSession!
        sceneView = v
        view = v
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let session = scanCoordinator.arSession else { return }
        session.run(scanCoordinator.arConfiguration())
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView?.session.pause()
    }
}

struct ARHostRepresentable: UIViewControllerRepresentable {
    let coordinator: ScanCoordinator
    func makeUIViewController(context: Context) -> ARHostVC {
        ARHostVC(scanCoordinator: coordinator)
    }
    func updateUIViewController(_ vc: ARHostVC, context: Context) {}
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
