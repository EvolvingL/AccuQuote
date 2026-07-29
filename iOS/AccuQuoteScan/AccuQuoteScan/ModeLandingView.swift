import SwiftUI

// MARK: - ModeLandingView (Tri-Mode Scanning build spec §1)
//
// The real entry point ContentView now shows first — ModePickerView plus the
// screen header/step-roadmap context, routing into whichever mode's existing
// flow. Room mode routes into the existing ReadyView/ScanCoordinator flow
// completely unchanged (lowest-risk integration — see the Phase 7 planning
// discussion: ReadyView has real polish/edge cases not worth touching).
// Space and Full Works route into their existing flow views, which were
// previously only reachable from Dev Tools.

struct ModeLandingView: View {
    @ObservedObject var coordinator: ScanCoordinator
    var onGuestTap: (() -> Void)? = nil
    /// Set to true while Space/Full Works are showing so ContentView can
    /// suppress the light-themed SlickFooter over their dark/AR chrome —
    /// see ContentView's isInFullScreenScanMode doc comment.
    @Binding var isInFullScreenScanMode: Bool

    @State private var selectedMode: ScanMode?
    // Fix #8 — one-time camera-access priming sheet, shown before the very
    // first scan of any mode. All three modes eventually trigger RoomPlan/
    // ARKit's own permission prompt from inside their own flow views, several
    // navigation levels deep — gating here, at the single hub all modes route
    // through, is simpler than duplicating the same one-time check three times.
    @State private var showCameraPrimer = false
    @State private var pendingMode: ScanMode?

    // Fix #9 — remembers the last mode picked so a returning user goes
    // straight into scanning instead of re-picking a mode every single time.
    // Stored as the enum's own String rawValue rather than inventing a
    // parallel representation. Empty string (no key collision with any real
    // ScanMode rawValue) means "never picked one" — first launch still shows
    // the picker. The picker itself remains one tap away via ReadyView's
    // existing back-chevron (onBackToModePicker).
    @AppStorage("aq_last_scan_mode") private var lastScanModeRaw: String = ""
    @State private var hasAutoRoutedOnce = false

    var body: some View {
        routedContent
            .onAppear {
                // Only auto-route on the very first appearance of this
                // screen in ready state — not after every dismissal back to
                // it (e.g. tapping the back-chevron from Room mode should
                // land on the picker, not immediately bounce back into Room).
                guard selectedMode == nil, hasAutoRoutedOnce == false,
                      let remembered = ScanMode(rawValue: lastScanModeRaw) else { return }
                hasAutoRoutedOnce = true
                selectedMode = remembered
            }
            .onChange(of: selectedMode) { mode in
                isInFullScreenScanMode = (mode == .space || mode == .fullWorks)
                if let mode { lastScanModeRaw = mode.rawValue }
            }
            .sheet(isPresented: $showCameraPrimer) {
                CameraPrimingSheet {
                    showCameraPrimer = false
                    UserDefaults.standard.set(true, forKey: "aq_camera_primer_seen")
                    selectedMode = pendingMode
                    pendingMode = nil
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
    }

    /// Routes to a mode, showing the one-time camera primer first if it
    /// hasn't been seen yet.
    private func selectMode(_ mode: ScanMode) {
        if UserDefaults.standard.bool(forKey: "aq_camera_primer_seen") {
            selectedMode = mode
        } else {
            pendingMode = mode
            showCameraPrimer = true
        }
    }

    // Pulled out of `body` as its own @ViewBuilder — the inline switch
    // inside a Group was hitting Swift's expression type-checker timeout
    // (real compiler error, not a stale-index false positive: confirmed via
    // a full xcodebuild run). Splitting each branch into a named function
    // gives the type-checker independent, much smaller expressions to solve.
    @ViewBuilder
    private var routedContent: some View {
        switch selectedMode {
        case nil:
            pickerScreen
        case .room:
            roomContent
        case .space:
            spaceContent
        case .fullWorks:
            fullWorksContent
        }
    }

    private var roomContent: some View {
        ReadyView(coordinator: coordinator, onGuestTap: onGuestTap, onBackToModePicker: { selectedMode = nil })
    }

    private var spaceContent: some View {
        SpaceScanFlowView(onDone: { selectedMode = nil })
    }

    private var fullWorksContent: some View {
        FullWorksFlowView(onDone: { selectedMode = nil })
    }

    private var pickerScreen: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    AQLogoView()
                    Text("Choose a scan mode")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(AQ.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 56)
            .padding(.bottom, 28)

            ModePickerView(
                onSelectRoom: { selectMode(.room) },
                onSelectSpace: { selectMode(.space) },
                onSelectFullWorks: { selectMode(.fullWorks) }
            )

            Spacer()

            if let onGuestTap {
                Button(action: onGuestTap) {
                    HStack(spacing: 5) {
                        Image(systemName: "dot.scope").font(.system(size: 12))
                        Text("Just want to scan a room? Try it free →")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(AQ.secondary)
                }
                .padding(.bottom, 28)
            }
        }
        .background(Color.white)
    }
}
