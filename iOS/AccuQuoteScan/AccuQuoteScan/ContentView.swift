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

    var body: some View {
        ZStack {
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
                    // Paywall gate: free users see dimensions only
                    if entitlement.isPaid {
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
        }
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
