import SwiftUI

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

struct StepDot: View {
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

struct StepConnector: View {
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

