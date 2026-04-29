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

// MARK: - Profile Gate View
// Shown until personalisation reaches profileUnlockThreshold (70%).
// The scan cannot be started until the AI profile is green.

struct ProfileGateView: View {
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
                VStack(alignment: .leading, spacing: 2) {
                    Text("AccuQuote")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(AQ.ink)
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

            // ── Unlock banner / question card ───────────────────────────────
            if isUnlocked {
                UnlockBanner()
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            } else {
                // Why-this-step explainer
                StepWhyCard(
                    icon: "sparkles",
                    color: AQ.blue,
                    headline: "Step 1 of 3 — Tell your AI about your business",
                    detail: "Without this, the AI quotes at industry-average rates — which are almost certainly wrong for you. Answer each question so it knows your actual day rate, material markup, VAT status, and how you price different jobs. The scan unlocks at \(profileUnlockThreshold)%."
                )
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 4)
            }

            // ── Question / generating ───────────────────────────────────────
            if !isUnlocked {
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
                                Text("Preparing more questions…")
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
            } else {
                Spacer()
            }

            // ── Bottom CTA ──────────────────────────────────────────────────
            VStack(spacing: 0) {
                Divider().background(AQ.rule).padding(.bottom, 16)

                if isUnlocked {
                    // Unlock button — prominent green
                    Button {
                        // ContentView watches profileReady — this view disappears automatically
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
                        .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                                   value: unlockPulse)
                    }
                    .padding(.horizontal, 24)
                    .onAppear { unlockPulse = true }
                } else {
                    // Add a document shortcut
                    Button { showDocumentSheet = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.badge.plus")
                                .font(.system(size: 14, weight: .medium))
                            Text("Upload a rate card to boost accuracy faster")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(AQ.blue)
                    }
                    .padding(.horizontal, 24)
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
    @State private var showOnboarding = false
    @State private var showManualEntry = false
    @State private var pulseIcon = false

    var isLiDAR: Bool { coordinator.scanMethod == .lidar }

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
            .padding(.bottom, 20)

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
            .padding(.bottom, 32)

            Text("Measure the Room")
                .font(.system(size: 36, weight: .bold))
                .foregroundColor(AQ.ink)
                .padding(.bottom, 10)

            ScanMethodBadge(method: coordinator.scanMethod)
                .padding(.bottom, 18)

            Text(isLiDAR
                 ? "Walk slowly around the room. LiDAR measures every surface in real time."
                 : "Sweep the camera around every wall or enter measurements manually.")
                .font(AQ.body(15))
                .foregroundColor(AQ.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .padding(.horizontal, 44)
                .padding(.bottom, 16)

            // Why this step matters
            StepWhyCard(
                icon: "cube.transparent",
                color: AQ.blue,
                headline: "Step 2 of 3 — Measure the room",
                detail: "The scan gives the AI the exact floor area, wall area, and ceiling height it needs to calculate how much material and how many labour days your quote should include. No guessing — every dimension feeds directly into the numbers."
            )
            .padding(.horizontal, 24)

            // Non-LiDAR: show method options inline
            if !isLiDAR {
                NonLiDARMethodCards(
                    onSweep: { coordinator.startScan() },
                    onManual: { showManualEntry = true }
                )
                .padding(.top, 28)
                .padding(.horizontal, 24)
            }

            Spacer()

            // ── CTA ─────────────────────────────────────────────────────────
            if isLiDAR {
                VStack(spacing: 0) {
                    Divider().background(AQ.rule).padding(.bottom, 20)
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
                    Text("LiDAR · iPhone 12 Pro or later")
                        .font(AQ.body(12))
                        .foregroundColor(AQ.secondary.opacity(0.7))
                        .padding(.top, 12)
                        .padding(.bottom, 36)
                }
            } else {
                Color.clear.frame(height: 36)
            }
        }
        .background(Color.white)
        .sheet(isPresented: $showOnboarding) {
            OnboardingSheet().environmentObject(questionEngine)
        }
        .sheet(isPresented: $showManualEntry) {
            ManualEntrySheet(coordinator: coordinator)
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

            VStack(alignment: .leading, spacing: 6) {
                Text("The more your AI knows, the more money you make per quote.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AQ.ink)
                    .lineSpacing(3)
                Text("Every answer trains your AI to use your actual day rate, markup, and terms — not guesses. Tradespeople who complete the profile typically recoup their subscription cost on the very first quote they send.")
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

// MARK: - Pose Fusion Scanning View

struct PoseFusionScanningView: View {
    @ObservedObject var coordinator: ScanCoordinator
    @State private var isHolding = false

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

    var body: some View {
        VStack(spacing: 0) {

            // Header
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AccuQuote")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(AQ.ink)
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

            // ── Step roadmap ────────────────────────────────────────────────
            HStack(spacing: 0) {
                StepDot(number: 1, label: "AI Profile", active: false, done: true, color: AQ.green)
                StepConnector(done: true)
                StepDot(number: 2, label: "Scan Room",  active: false, done: true, color: AQ.green)
                StepConnector(done: true)
                StepDot(number: 3, label: "Get Quote",  active: true,  done: false, color: AQ.blue)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 20)

            Divider().background(AQ.rule).padding(.horizontal, 24).padding(.bottom, 24)

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
                    Text("Measure Again")
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
        .fullScreenCover(isPresented: $showJobDescription) {
            JobDescriptionView(result: result, coordinator: coordinator)
        }
    }
}

// MARK: - Job Description View

struct JobDescriptionView: View {
    let result: RoomDimensions
    @ObservedObject var coordinator: ScanCoordinator
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var questionEngine: QuestionEngine

    @StateObject private var recorder = VoiceRecorder()
    @State private var jobDescription = ""
    @State private var customerName   = ""
    @State private var showQuote      = false
    @State private var showTypeInput  = false
    @FocusState private var typeFocused: Bool

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
                            Text("\(result.lengthStr) × \(result.widthStr) × \(result.heightStr)m · \(result.floorAreaStr)m² · \(result.roomType.capitalized)")
                                .font(.system(size: 12, weight: .medium)).foregroundColor(AQ.blue)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(AQ.blue.opacity(0.07)).cornerRadius(20)
                        .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 28)

                        Text("What needs doing?")
                            .font(.system(size: 28, weight: .bold)).foregroundColor(AQ.ink)
                            .padding(.horizontal, 24).padding(.bottom, 8)

                        Text("Describe the job by voice. The more detail, the more accurate the quote.")
                            .font(AQ.body(15)).foregroundColor(AQ.secondary)
                            .lineSpacing(4).padding(.horizontal, 24).padding(.bottom, 16)

                        // Why this step matters
                        StepWhyCard(
                            icon: "waveform",
                            color: AQ.blue,
                            headline: "Step 3 of 3 — Describe the job",
                            detail: "The AI uses your description to figure out scope: how many labour days, which materials, whether there's prep or waste removal. Say things like 'full bathroom refit, remove old suite, tile floor and walls' — the more specific you are, the tighter the numbers."
                        )
                        .padding(.horizontal, 24).padding(.bottom, 28)

                        // ── Voice waveform / transcript area ─────────────────
                        VoiceInputCard(
                            recorder: recorder,
                            transcript: $jobDescription
                        )
                        .padding(.horizontal, 24).padding(.bottom, 20)

                        // ── Typed fallback ───────────────────────────────────
                        if showTypeInput || !jobDescription.isEmpty {
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
                                    .frame(minHeight: 130)
                                    .padding(12)
                                    .scrollContentBackground(.hidden)
                            }
                            .background(AQ.fill).cornerRadius(14)
                            .overlay(RoundedRectangle(cornerRadius: 14)
                                .stroke(typeFocused ? AQ.blue : AQ.rule, lineWidth: 1)
                                .animation(.easeInOut(duration: 0.15), value: typeFocused))
                            .padding(.horizontal, 24).padding(.bottom, 20)
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
                    HStack(spacing: 12) {
                        // Keyboard toggle
                        Button {
                            showTypeInput.toggle()
                            if showTypeInput { typeFocused = true }
                        } label: {
                            Image(systemName: showTypeInput ? "keyboard.chevron.compact.down" : "keyboard")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(showTypeInput ? AQ.blue : AQ.secondary)
                                .frame(width: 48, height: 48)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(showTypeInput ? AQ.blue.opacity(0.4) : AQ.rule, lineWidth: 1)
                                )
                        }

                        // Generate quote
                        Button {
                            typeFocused = false
                            showQuote = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 15, weight: .semibold))
                                Text("Generate Quote")
                                    .font(.system(size: 17, weight: .semibold))
                            }
                            .foregroundColor(canProceed ? .white : AQ.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(canProceed ? AQ.blue : AQ.fill)
                            .cornerRadius(12)
                            .animation(.easeInOut(duration: 0.15), value: canProceed)
                        }
                        .disabled(!canProceed)
                    }
                    .padding(.horizontal, 24).padding(.vertical, 14)
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
        }
        .fullScreenCover(isPresented: $showQuote) {
            QuoteView(result: result, jobDescription: jobDescription,
                      customerName: customerName, coordinator: coordinator)
                .environmentObject(questionEngine)
        }
        .onTapGesture { typeFocused = false }
        .onReceive(recorder.$transcript) { t in
            if !t.isEmpty { jobDescription = t }
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
            DispatchQueue.main.async {
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

struct QuoteLineItem: Identifiable {
    let id = UUID()
    let description: String
    let qty: Double
    let unit: String
    let unitPrice: Double
    var total: Double { qty * unitPrice }
}

struct GeneratedQuote {
    let labourDays: Double
    let labourRate: Double
    let labourTotal: Double
    let items: [QuoteLineItem]
    let materialsTotal: Double
    let subtotal: Double
    let vatRate: Double
    let vatAmount: Double
    let grandTotal: Double
    let notes: String
    let customerName: String
    let jobDescription: String
}

// MARK: - Quote View

struct QuoteView: View {
    let result: RoomDimensions
    let jobDescription: String
    let customerName: String
    @ObservedObject var coordinator: ScanCoordinator
    @EnvironmentObject var questionEngine: QuestionEngine
    @Environment(\.dismiss) var dismiss

    @State private var quote: GeneratedQuote?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var loadingStep = 0

    private let loadingSteps = [
        "Reading room dimensions…",
        "Analysing job description…",
        "Calculating materials…",
        "Applying your rates…",
        "Building quote…",
    ]

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    QuoteLoadingView(step: loadingStep, steps: loadingSteps)
                } else if let error = errorMessage {
                    QuoteErrorView(message: error) {
                        errorMessage = nil
                        isLoading = true
                        Task { await generateQuote() }
                    }
                } else if let quote = quote {
                    QuoteResultView(quote: quote, result: result) {
                        // Start over
                        dismiss()
                        coordinator.reset()
                    }
                }
            }
            .navigationTitle("Quote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !isLoading {
                        Button("Back") { dismiss() }
                            .foregroundColor(AQ.secondary)
                    }
                }
            }
        }
        .task { await generateQuote() }
    }

    private func generateQuote() async {
        isLoading = true
        errorMessage = nil

        // Animate through loading steps
        let stepTask = Task {
            for i in 0..<loadingSteps.count {
                try? await Task.sleep(nanoseconds: 700_000_000)
                await MainActor.run { loadingStep = i }
            }
        }

        let context = questionEngine.claudeContext()
        let floorArea = result.floorArea
        let wallArea  = result.wallArea

        let prompt = """
        You are an expert quoting assistant for a UK tradesperson.

        \(context.isEmpty ? "" : context + "\n\n")
        ROOM: \(result.roomType)
        DIMENSIONS: \(result.lengthStr)m × \(result.widthStr)m × \(result.heightStr)m
        FLOOR AREA: \(String(format: "%.1f", floorArea))m²
        WALL AREA: \(String(format: "%.1f", wallArea))m²
        DOORS: \(result.doorCount)   WINDOWS: \(result.windowCount)

        JOB DESCRIPTION: \(jobDescription)

        Produce a detailed, accurate quote. Use the tradesperson's actual rates from their profile above if available, otherwise use realistic UK market rates.

        Respond with ONLY valid JSON, no markdown:
        {
          "labourDays": 2.0,
          "labourRate": 280.0,
          "items": [
            { "description": "Item name", "qty": 1.0, "unit": "each", "unitPrice": 12.50 }
          ],
          "vatRate": 20,
          "notes": "Any important notes, inclusions, exclusions"
        }
        """

        guard let url = URL(string: ANTHROPIC_API_URL) else {
            stepTask.cancel()
            await MainActor.run {
                errorMessage = "Could not connect to Anthropic API."
                isLoading = false
            }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(ANTHROPIC_API_KEY, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 45

        let body: [String: Any] = [
            "model": "claude-sonnet-4-6",
            "max_tokens": 2048,
            "messages": [["role": "user", "content": prompt]]
        ]

        do {
            let bodyData = try JSONSerialization.data(withJSONObject: body)
            request.httpBody = bodyData
            let (data, _) = try await URLSession.shared.data(for: request)

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let content = json["content"] as? [[String: Any]],
               let text = content.first?["text"] as? String,
               let jsonStart = text.firstIndex(of: "{"),
               let jsonEnd = text.lastIndex(of: "}") {
                let slice = String(text[jsonStart...jsonEnd])
                if let sliceData = slice.data(using: .utf8),
                   let parsed = try? JSONSerialization.jsonObject(with: sliceData) as? [String: Any] {
                    let q = buildQuote(from: parsed)
                    stepTask.cancel()
                    await MainActor.run { quote = q; isLoading = false }
                    return
                }
            }
            throw URLError(.cannotParseResponse)
        } catch {
            stepTask.cancel()
            await MainActor.run {
                errorMessage = "Failed to generate quote. Please check your connection and try again."
                isLoading = false
            }
        }
    }

    private func buildQuote(from json: [String: Any]) -> GeneratedQuote {
        let labourDays = (json["labourDays"] as? Double) ?? 1.0
        let labourRate = (json["labourRate"] as? Double) ?? 280.0
        let labourTotal = labourDays * labourRate
        let vatRate = (json["vatRate"] as? Double) ?? 20.0
        let notes = (json["notes"] as? String) ?? ""

        var items: [QuoteLineItem] = []
        if let rawItems = json["items"] as? [[String: Any]] {
            for raw in rawItems {
                let desc  = (raw["description"] as? String) ?? "Item"
                let qty   = (raw["qty"] as? Double) ?? 1.0
                let unit  = (raw["unit"] as? String) ?? "each"
                let price = (raw["unitPrice"] as? Double) ?? 0.0
                items.append(QuoteLineItem(description: desc, qty: qty, unit: unit, unitPrice: price))
            }
        }

        let materialsTotal = items.reduce(0) { $0 + $1.total }
        let subtotal = labourTotal + materialsTotal
        let vatAmount = subtotal * (vatRate / 100)
        let grandTotal = subtotal + vatAmount

        return GeneratedQuote(
            labourDays: labourDays, labourRate: labourRate, labourTotal: labourTotal,
            items: items, materialsTotal: materialsTotal,
            subtotal: subtotal, vatRate: vatRate, vatAmount: vatAmount, grandTotal: grandTotal,
            notes: notes, customerName: customerName, jobDescription: jobDescription
        )
    }
}

// MARK: - Quote Loading View

struct QuoteLoadingView: View {
    let step: Int
    let steps: [String]
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle().fill(AQ.blue.opacity(0.07)).frame(width: 100, height: 100)
                    .scaleEffect(pulse ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: pulse)
                Circle().fill(AQ.blue.opacity(0.13)).frame(width: 72, height: 72)
                Image(systemName: "sparkles")
                    .font(.system(size: 26, weight: .light))
                    .foregroundColor(AQ.blue)
            }
            .onAppear { pulse = true }
            .padding(.bottom, 36)

            Text("Building your quote")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(AQ.ink)
                .padding(.bottom, 10)

            Text(step < steps.count ? steps[step] : "Almost done…")
                .font(AQ.body(15))
                .foregroundColor(AQ.secondary)
                .animation(.easeInOut(duration: 0.3), value: step)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
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
    @State private var shareText: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                // Grand total hero
                VStack(spacing: 6) {
                    Text("Total")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AQ.secondary)
                        .kerning(0.8)
                        .textCase(.uppercase)
                    Text("£\(Int(quote.grandTotal).formatted())")
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

                // Labour
                QuoteSectionHeader(title: "Labour")
                QuoteRow(
                    label: "\(String(format: "%.1f", quote.labourDays)) day\(quote.labourDays == 1 ? "" : "s") @ £\(Int(quote.labourRate))/day",
                    value: "£\(Int(quote.labourTotal).formatted())",
                    bold: false
                )
                Divider().background(AQ.rule).padding(.leading, 24)

                // Materials
                if !quote.items.isEmpty {
                    QuoteSectionHeader(title: "Materials & Items")
                    ForEach(quote.items) { item in
                        QuoteRow(
                            label: "\(item.description)\n\(formatQty(item.qty)) \(item.unit) × £\(String(format: "%.2f", item.unitPrice))",
                            value: "£\(String(format: "%.2f", item.total))",
                            bold: false,
                            multiline: true
                        )
                        Divider().background(AQ.rule).padding(.leading, 24)
                    }
                }

                // Totals
                QuoteSectionHeader(title: "Summary")
                QuoteRow(label: "Subtotal", value: "£\(Int(quote.subtotal).formatted())", bold: false)
                Divider().background(AQ.rule).padding(.leading, 24)
                QuoteRow(label: "VAT (\(Int(quote.vatRate))%)", value: "£\(String(format: "%.2f", quote.vatAmount))", bold: false)
                Divider().background(AQ.rule).padding(.leading, 24)
                QuoteRow(label: "Total", value: "£\(Int(quote.grandTotal).formatted())", bold: true)
                Divider().background(AQ.rule)

                // Notes
                if !quote.notes.isEmpty {
                    QuoteSectionHeader(title: "Notes & Inclusions")
                    Text(quote.notes)
                        .font(AQ.body(14))
                        .foregroundColor(AQ.secondary)
                        .lineSpacing(5)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                    Divider().background(AQ.rule)
                }

                // Actions
                VStack(spacing: 10) {
                    // Share as text
                    Button {
                        shareText = buildShareText()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Share Quote")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 17)
                        .background(AQ.blue).cornerRadius(14)
                    }

                    Button(action: onStartOver) {
                        Text("Start New Quote")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(AQ.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
        }
        .background(Color.white)
        .sheet(item: Binding(
            get: { shareText.map { ShareContent(text: $0) } },
            set: { if $0 == nil { shareText = nil } }
        )) { content in
            ShareSheet(text: content.text)
        }
    }

    private func formatQty(_ qty: Double) -> String {
        qty == qty.rounded() ? "\(Int(qty))" : String(format: "%.1f", qty)
    }

    private func buildShareText() -> String {
        var lines = ["QUOTE — AccuQuote"]
        if !quote.customerName.isEmpty { lines.append("Customer: \(quote.customerName)") }
        lines.append("Room: \(result.roomType.capitalized) \(result.lengthStr)×\(result.widthStr)×\(result.heightStr)m")
        lines.append("Work: \(quote.jobDescription)")
        lines.append("")
        lines.append("Labour: £\(Int(quote.labourTotal))")
        lines.append("Materials: £\(Int(quote.materialsTotal))")
        lines.append("Subtotal: £\(Int(quote.subtotal))")
        lines.append("VAT (\(Int(quote.vatRate))%): £\(String(format: "%.2f", quote.vatAmount))")
        lines.append("TOTAL: £\(Int(quote.grandTotal)) inc. VAT")
        if !quote.notes.isEmpty { lines.append("\nNotes: \(quote.notes)") }
        lines.append("\nGenerated by AccuQuote")
        return lines.joined(separator: "\n")
    }
}

struct ShareContent: Identifiable {
    let id = UUID()
    let text: String
}

struct ShareSheet: UIViewControllerRepresentable {
    let text: String
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Quote row components

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
