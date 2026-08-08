import SwiftUI

// MARK: - Ready View

struct ReadyView: View {
    @ObservedObject var coordinator: ScanCoordinator
    @EnvironmentObject var questionEngine: QuestionEngine
    var onGuestTap: (() -> Void)? = nil
    /// Set only when reached via ModePickerView (§1) — shows a back chevron
    /// so the user can return to the picker instead of being stuck in Room
    /// mode. nil for GuestLandingView's own use of ReadyView, which has no
    /// picker to go back to.
    var onBackToModePicker: (() -> Void)? = nil
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
                if let onBackToModePicker {
                    Button(action: onBackToModePicker) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AQ.ink)
                            .frame(width: 32, height: 32)
                            .background(AQ.fill)
                            .clipShape(Circle())
                    }
                    .padding(.trailing, 4)
                }
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
                .font(.largeTitle.weight(.bold))   // #1
                .minimumScaleFactor(0.7)            // #7
                .multilineTextAlignment(.center)
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

