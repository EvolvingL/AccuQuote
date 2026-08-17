import SwiftUI

// Threshold below which we prompt for quick-setup before generating a quote
let profileQuickSetupThreshold = 50

struct ContentView: View {
    @StateObject private var coordinator = ScanCoordinator()
    @EnvironmentObject var questionEngine: QuestionEngine
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var entitlement: EntitlementManager
    @ObservedObject private var notifications = NotificationService.shared

    // Guest mode: bypasses profile, goes straight to scan-only flow
    @State private var showGuest = false
    // True while ModeLandingView is showing Space mode or Full Works —
    // both are full-screen dark/AR flows with their own chrome, so the
    // light-themed SlickFooter (and its white background bar) must not
    // overlay them the way it correctly does over the light Room-mode screens.
    @State private var isInFullScreenScanMode = false
    @State private var showProfileMenu = false

    // Persistent profile access was previously only reachable from ReadyView's
    // own top bar, so users on any other screen (History, Results, Quote,
    // error/needs-review states) had no way back to Settings/Sign out/Home
    // without navigating through "describe the job" first. This overlay makes
    // the profile button globally reachable, suppressed only where a
    // full-screen capture UI is active and any overlay chrome would obstruct it.
    private var profileButtonHidden: Bool {
        if case .scanning = coordinator.state { return true }
        if isInFullScreenScanMode { return true }
        return false
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if showGuest {
                // ── Guest / free tool flow ──────────────────────────────
                GuestLandingView(showGuest: $showGuest)
                    .transition(.move(edge: .trailing).combined(with: .opacity))

            } else {
                // ── Main app flow ───────────────────────────────────────
                switch coordinator.state {
                case .ready:
                    ModeLandingView(coordinator: coordinator, onGuestTap: { showGuest = true },
                                     isInFullScreenScanMode: $isInFullScreenScanMode)
                case .scanning:
                    ScanningView(coordinator: coordinator)
                case .processing:
                    ProcessingView()
                case .complete(let result):
                    // Paywall gate: free-tier users get 3 free quotes (server-enforced,
                    // see FREE_QUOTE_LIMIT in server/index.js) before quote generation is
                    // blocked — so gating here on `isPaid` alone locked out every free
                    // user before they'd used any of their allowance. Only show the
                    // locked state once the allowance is actually exhausted; otherwise
                    // let them through to attempt generation, where the server's 403
                    // (surfaced via QuoteGenerationService's .failed state) is the real
                    // enforcement point.
                    if entitlement.isPaid || (entitlement.freeQuotesRemaining ?? 1) > 0 {
                        ResultView(result: result, coordinator: coordinator)
                    } else {
                        LockedResultView(result: result, coordinator: coordinator)
                    }
                case .needsReview(let room, let result, let confidence):
                    ScanNeedsReviewView(coordinator: coordinator, room: room, result: result, confidence: confidence)
                case .error(let message):
                    ErrorView(message: message, coordinator: coordinator)
                }
            }

            if !showGuest && !profileButtonHidden {
                ProfileIconButton(pct: questionEngine.personalisation) {
                    showProfileMenu = true
                }
                .padding(.top, 56)
                .padding(.trailing, 24)
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $showProfileMenu) {
            ProfileMenuSheet().environmentObject(questionEngine)
        }
        .animation(.easeInOut(duration: 0.2), value: profileButtonHidden)
        .animation(.easeInOut(duration: 0.4), value: showGuest)
        // #6/#30: AccuQuote is a deliberately light, paper-document themed quoting tool —
        // its quote PDFs, proposals and forms read as printed documents. The hardcoded
        // AQ palette encodes the light values throughout. We keep .light as the design
        // intent so the document aesthetic is consistent on every device.
        .preferredColorScheme(.light)
        .tint(AQ.blue)   // #global consistent accent for all system controls
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if case .scanning = coordinator.state {
                EmptyView()
            } else if isInFullScreenScanMode {
                EmptyView()
            } else {
                SlickFooter()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .aqSignOut)) { _ in
            auth.signOut()
            entitlement.clear()
        }
        // AccuScan→AccuQuote Funnel build spec §4.3 — the two import paths
        // (cold launch / already-running with a pending handoff, and a live
        // accuquote://import deep link) both funnel through the same
        // HandoffImporter.importIfPending so dedupe has one source of truth.
        .task {
            HandoffImporter.importIfPending(into: coordinator)
        }
        .onReceive(NotificationCenter.default.publisher(for: .aqHandoffDeepLink)) { _ in
            HandoffImporter.importIfPending(into: coordinator)
        }
        // Fix #14 — one-time primer sheet shown before the real notification
        // permission prompt, triggered after the user's first successful
        // quote generation (see QuoteGenerationService.persistToHistory /
        // NotificationService.requestPermissionAfterFirstQuote).
        .sheet(isPresented: $notifications.showPrimerRequested) {
            NotificationPrimerSheet {
                NotificationService.shared.primerContinueTapped()
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }
}

struct SlickFooter: View {
    var body: some View {
        Link(destination: URL(string: "https://slickdigital.co.uk")!) {
            Text("Built by Slick")
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(Color(red: 0.52, green: 0.52, blue: 0.56))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.white)
    }
}
