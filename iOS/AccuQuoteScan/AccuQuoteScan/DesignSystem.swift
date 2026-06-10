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
