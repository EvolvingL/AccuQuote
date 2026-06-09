import SwiftUI

// MARK: - Corner Radius Tokens (#17)
// Single source of truth for all corner radii — eliminates the 7 different
// magic numbers scattered across the codebase.

enum Radius {
    static let xs:         CGFloat = 8    // small chips, tags, wall tiles
    static let small:      CGFloat = 10   // room type pills
    static let medium:     CGFloat = 12   // input fields, cards
    static let large:      CGFloat = 14   // primary buttons, scan cards
    static let xl:         CGFloat = 16   // CTAs, major buttons
    static let xxl:        CGFloat = 20   // glass HUD cards, modals
}

// MARK: - ScaleButtonStyle (#15)
// Provides tactile press feedback on every button — previously buttons had
// no visual response to touch on dark backgrounds.

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Reduce Motion helpers (#11)
// Use these wrappers instead of .animation() directly to respect
// the user's Reduce Motion accessibility setting.

extension Animation {
    /// Returns the animation, or .none when Reduce Motion is enabled.
    static func accessible(_ animation: Animation,
                            reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

extension View {
    /// Applies animation only when Reduce Motion is off.
    func accessibleAnimation<V: Equatable>(_ animation: Animation,
                                            value: V,
                                            reduceMotion: Bool) -> some View {
        self.animation(reduceMotion ? nil : animation, value: value)
    }
}
