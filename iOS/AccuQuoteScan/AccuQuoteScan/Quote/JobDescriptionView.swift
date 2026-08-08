import SwiftUI

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
    @State private var showSpaceScan  = false   // §3.3 — Space mode "attach to quote"
    @State private var quickSetupDismissedByUser = false   // Fix #14: track intentional dismiss
    @FocusState private var typeFocused: Bool

    private let customerNameLimit = 120   // Fix #16: cap customer name to prevent API abuse

    private var effectiveRoomType: String { roomTypeOverride.isEmpty ? result.roomType : roomTypeOverride }

    // Fix #11: >= 10 not > 10 — "Paint wall" (10 chars) is a valid job description
    var canProceed: Bool { jobDescription.trimmingCharacters(in: .whitespaces).count >= 10 }

    var body: some View {
        NavigationStack {
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
                            .font(.largeTitle.weight(.bold))   // #1
                            .minimumScaleFactor(0.7)           // #7
                            .foregroundColor(AQ.ink)
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
                                // Fix #16 — the panel below has a .transition
                                // but this toggle wasn't wrapped in
                                // withAnimation, so it snapped in/out instead
                                // of animating like the transition implies.
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    showVoicePanel.toggle()
                                }
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

                        // ── Space mode — measure a detail and attach it (§3.3) ──
                        if SpaceCaptureCoordinator.isSupported {
                            Button {
                                typeFocused = false
                                showSpaceScan = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "viewfinder")
                                        .font(.system(size: 13, weight: .medium))
                                    Text("Measure a detail (void, window, door frame)")
                                        .font(.system(size: 13, weight: .medium))
                                }
                                .foregroundColor(AQ.blue)
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .background(AQ.blue.opacity(0.08)).cornerRadius(12)
                            }
                            .padding(.horizontal, 24).padding(.bottom, 16)
                        }

                        // Customer name — Fix #16: capped at 120 chars
                        FieldLabel("Customer name (optional)")
                        TextField("e.g. Mr Smith — 14 Oak Street", text: $customerName)
                            .font(.system(size: 16))
                            .onChange(of: customerName) { v in
                                if v.count > customerNameLimit {
                                    customerName = String(v.prefix(customerNameLimit))
                                }
                            }
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
                    Button("Back") {
                        // Fix #15: stop recording before dismiss so AVAudioEngine tap is released
                        if recorder.isRecording { recorder.stop() }
                        dismiss()
                    }
                    .foregroundColor(AQ.secondary)
                }
            }
            // Fix #16 — removed the auto-show-after-0.6s of the voice panel.
            // It used to pop open unprompted on every visit to an empty job
            // description, competing with the mic button for attention
            // instead of just being one deliberate tap away like every other
            // input method here. The mic button (above) is the only
            // affordance needed to reveal it now.
        }
        .fullScreenCover(isPresented: $showQuote) {
            QuoteView(result: result, jobDescription: jobDescription,
                      customerName: customerName, coordinator: coordinator)
                .environmentObject(questionEngine)
        }
        .fullScreenCover(isPresented: $showSpaceScan) {
            SpaceScanFlowView(
                onDone: { showSpaceScan = false },
                onAttach: { note in
                    // §3.3 — fold the measurement note straight into the job
                    // description, the one field that flows into both quote-
                    // section discovery and every section's generation prompt.
                    if jobDescription.isEmpty {
                        jobDescription = note
                    } else {
                        jobDescription += "\n" + note
                    }
                }
            )
        }
        .sheet(isPresented: $showQuickSetup, onDismiss: {
            // Fix #14: only open QuoteView when the user completed setup via onContinue,
            // not when they swiped the sheet down — tracked by quickSetupDismissedByUser
            if quickSetupDismissedByUser {
                quickSetupDismissedByUser = false
                showQuote = true
            }
        }) {
            QuickSetupSheet(onContinue: {
                quickSetupDismissedByUser = true
                showQuickSetup = false
            })
            .environmentObject(questionEngine)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .onTapGesture { typeFocused = false }
        // Fix #12/#13: only update jobDescription from voice when the recorder is
        // actively recording and the text field is not being edited concurrently.
        // Append the transcript rather than replacing, so typed text is preserved.
        .onReceive(recorder.$transcript) { t in
            guard recorder.isRecording, !t.isEmpty else { return }
            jobDescription = t
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
