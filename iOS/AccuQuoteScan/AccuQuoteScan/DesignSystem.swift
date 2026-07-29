import SwiftUI

// MARK: - Corner Radius Tokens (#17)

enum AQRadius {
    static let xs:     CGFloat = 8
    static let small:  CGFloat = 10
    static let medium: CGFloat = 12
    static let large:  CGFloat = 14
    static let xl:     CGFloat = 16
    static let xxl:    CGFloat = 20
}

// MARK: - ScaleButtonStyle (#15)

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Reduce Motion helpers (#11)

extension View {
    func accessibleAnimation<V: Equatable>(_ animation: Animation,
                                            value: V,
                                            reduceMotion: Bool) -> some View {
        self.animation(reduceMotion ? nil : animation, value: value)
    }
}

// MARK: - Currency formatting (#24)
// Shows pence only when present so totals never silently lose precision
// (£1,234.56 stays £1,234.56; £1,200.00 shows as £1,200).

enum Money {
    static func gbp(_ amount: Double) -> String {
        // Guard against NaN/Inf and astronomically large values that would trap
        // in Int(...). A single poisoned value (e.g. unitPrice 1e308 from the AI)
        // must never crash the quote/history/deposit screens.
        guard amount.isFinite else { return "£0" }
        let a = min(max(amount, -1_000_000_000), 1_000_000_000)   // clamp to ±£1bn
        return a.truncatingRemainder(dividingBy: 1) == 0
            ? "£\(Int(a).formatted())"
            : String(format: "£%.2f", a)
    }
}

// MARK: - Camera priming sheet (Fix #8)
//
// Shown once per install, right before the very first scan of any mode —
// explains briefly why AccuQuote needs camera/LiDAR access before the
// system's own permission prompt appears (triggered internally inside
// ScanCoordinator.beginLiDARSession(), which now does an explicit
// AVCaptureDevice.authorizationStatus check rather than leaving it entirely
// implicit). Shared by ModeLandingView (main flow, all three modes) and
// GuestScanView (separate entry point, same one-time UserDefaults flag).
// Deliberately minimal — one icon, one line, one "Continue" button.
struct CameraPrimingSheet: View {
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 4)
                .padding(.top, 12)

            Image(systemName: "camera.fill")
                .font(.system(size: 40))
                .foregroundColor(AQ.blue)
                .accessibilityHidden(true)

            Text("AccuQuote needs your camera")
                .font(AQ.title(20))
                .foregroundColor(AQ.ink)

            Text("Camera and LiDAR access lets AccuQuote measure rooms in 3D as you walk around them. Nothing is recorded or shared.")
                .font(AQ.body(14))
                .foregroundColor(AQ.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button(action: onContinue) {
                Text("Continue")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(AQ.blue)
                    .cornerRadius(AQRadius.large)
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .background(Color.white.ignoresSafeArea())
    }
}

// MARK: - Notification priming sheet (Fix #14)
//
// Shown once, after the user's first successful quote generation, before
// NotificationService.requestPermission() triggers iOS's own permission
// dialog — same visual pattern as CameraPrimingSheet just above.
struct NotificationPrimerSheet: View {
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 4)
                .padding(.top, 12)

            Image(systemName: "bell.badge.fill")
                .font(.system(size: 40))
                .foregroundColor(AQ.blue)
                .accessibilityHidden(true)

            Text("Stay on top of your quotes")
                .font(AQ.title(20))
                .foregroundColor(AQ.ink)

            Text("Turn on notifications and AccuQuote will let you know about quote updates and reminders — you can change this anytime in Settings.")
                .font(AQ.body(14))
                .foregroundColor(AQ.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button(action: onContinue) {
                Text("Continue")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(AQ.blue)
                    .cornerRadius(AQRadius.large)
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .background(Color.white.ignoresSafeArea())
    }
}
