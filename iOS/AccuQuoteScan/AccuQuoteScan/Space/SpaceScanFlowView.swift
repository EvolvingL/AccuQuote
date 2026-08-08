import SwiftUI

// MARK: - SpaceScanFlowView (Tri-Mode Scanning build spec §3)
//
// Top-level switch over SpaceCaptureState, mirroring how ContentView
// switches over ScanCoordinator.state — kept as its own flow view rather than
// folded into ContentView because the mode picker (§1, not yet built) is what
// will actually decide which flow to present; until then this is reachable
// standalone (see DevToolsView's "Try Space mode" row) for on-device testing.

struct SpaceScanFlowView: View {
    @StateObject private var coordinator = SpaceCaptureCoordinator()
    @ObservedObject private var entitlement = EntitlementManager.shared
    @State private var showManualEntry = false
    var onDone: () -> Void = {}
    /// Called with the §3.3 quote-attachment note text when the user taps
    /// "Attach to quote" on a result screen — nil (the default) hides that
    /// button entirely, e.g. when this flow is launched standalone from Dev
    /// Tools with nothing to attach to.
    var onAttach: ((String) -> Void)?

    var body: some View {
        ZStack {
            // Gate at entry: Space mode is a Pro feature. Free users must see
            // a locked/upgrade screen before capture starts at all — mirrors
            // Room mode's paywall gate in ContentView, just moved earlier in
            // the flow since Space mode has no free "dimensions only" preview
            // to fall back to the way Room mode's LockedResultView does.
            if !entitlement.isPaid {
                SpaceLockedView(onCancel: onDone)
            } else {
                switch coordinator.state {
                case .placingVolume, .scanning:
                    SpaceScanningView(coordinator: coordinator)
                case .processing:
                    ProcessingView()
                case .complete(let dimensions):
                    SpaceResultView(dimensions: dimensions, coordinator: coordinator, onDone: onDone, onAttach: onAttach)
                case .completeFrame(let reveal):
                    SpaceFrameResultView(reveal: reveal, coordinator: coordinator, onDone: onDone, onAttach: onAttach)
                case .unsupported:
                    SpaceManualEntryView(onSubmit: { w, h, d in
                        let dims = SpaceDimensions(width: w, height: h, depth: d, scanMethod: .manual)
                        coordinator.state = .complete(dims)
                    }, onCancel: onDone)
                case .error(let message):
                    SpaceErrorView(message: message, onRetry: { coordinator.start() }, onCancel: onDone)
                }
            }
        }
        .onAppear {
            guard entitlement.isPaid else { return }
            coordinator.start()
        }
        .onDisappear { coordinator.reset() }
    }
}

// MARK: - Locked state (Pro gate)
//
// Shown instead of starting capture at all when the user is on the free
// tier. Kept Space-mode-specific rather than reusing Room mode's
// LockedResultView, which expects an already-completed RoomDimensions result
// to display — Space mode has nothing to show yet at this point, since
// gating happens before SpaceCaptureCoordinator.start() is ever called.
struct SpaceLockedView: View {
    var onCancel: () -> Void
    @State private var showPaywall = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(AQ.secondary.opacity(0.4))
            Text("Space mode is a Pro feature")
                .font(AQ.title(17))
                .foregroundColor(AQ.ink)
                .multilineTextAlignment(.center)
            Text("Upgrade to scan voids, alcoves, and awkward spaces with LiDAR — plus everything else in AccuQuote Pro.")
                .font(AQ.body(14))
                .foregroundColor(AQ.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            VStack(spacing: 12) {
                Button { showPaywall = true } label: {
                    Text("See plans")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AQ.blue)
                        .cornerRadius(14)
                }
                Button("Cancel", action: onCancel)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AQ.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Color.white)
        .sheet(isPresented: $showPaywall) {
            PaywallSheet()
                .environmentObject(EntitlementManager.shared)
                .environmentObject(AuthManager.shared)
        }
    }
}

// MARK: - Non-LiDAR fallback (§3.2 "Space mode requires LiDAR")

struct SpaceManualEntryView: View {
    var onSubmit: (Double, Double, Double) -> Void
    var onCancel: () -> Void

    @State private var widthText = ""
    @State private var heightText = ""
    @State private var depthText = ""

    private func validMM(_ text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: ",", with: ".")
        guard let mm = Double(cleaned), mm > 0, mm <= 10_000 else { return nil }
        return mm / 1000
    }

    private var canSubmit: Bool {
        validMM(widthText) != nil && validMM(heightText) != nil && validMM(depthText) != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("Enter Void Measurements")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(AQ.ink)
                Text("Space mode needs a LiDAR sensor, which this device doesn't have. Use a tape measure instead.")
                    .font(AQ.body(14))
                    .foregroundColor(AQ.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(.top, 48)
            .padding(.bottom, 36)

            VStack(spacing: 14) {
                SpaceManualField(label: "Width",  hint: "e.g. 560", text: $widthText)
                SpaceManualField(label: "Height", hint: "e.g. 450", text: $heightText)
                SpaceManualField(label: "Depth",  hint: "e.g. 580", text: $depthText)
            }
            .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 12) {
                Divider().background(AQ.rule)
                Button {
                    guard let w = validMM(widthText), let h = validMM(heightText), let d = validMM(depthText) else { return }
                    onSubmit(w, h, d)
                } label: {
                    Text("Save Measurements")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(canSubmit ? AQ.blue : AQ.blue.opacity(0.35))
                        .cornerRadius(14)
                }
                .disabled(!canSubmit)
                Button("Cancel", action: onCancel)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AQ.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .background(Color.white)
    }
}

private struct SpaceManualField: View {
    let label: String
    let hint: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AQ.secondary)
                .frame(width: 70, alignment: .leading)
            TextField(hint, text: $text)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(AQ.ink)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity)
            Text("mm")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(AQ.secondary)
                .padding(.leading, 6)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 12).stroke(AQ.rule, lineWidth: 1))
    }
}

// MARK: - Error state

struct SpaceErrorView: View {
    let message: String
    var onRetry: () -> Void
    var onCancel: () -> Void

    // Fix #11 — same shared classification as ErrorView/QuoteErrorView/
    // FullWorksErrorView, so all four error screens agree on when "Try
    // Again" is actually meaningful to show.
    private var isRetryable: Bool { ScanErrorClassifier.isRetryable(message) }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: isRetryable ? "exclamationmark.triangle" : "lock.circle")
                .font(.system(size: 40))
                .foregroundColor(AQ.secondary)
            Text(message)
                .font(AQ.body(15))
                .foregroundColor(AQ.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            VStack(spacing: 12) {
                if isRetryable {
                    Button(action: onRetry) {
                        Text("Try Again")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(AQ.blue)
                            .cornerRadius(14)
                    }
                }
                Button(isRetryable ? "Cancel" : "Close", action: onCancel)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AQ.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Color.white)
    }
}
