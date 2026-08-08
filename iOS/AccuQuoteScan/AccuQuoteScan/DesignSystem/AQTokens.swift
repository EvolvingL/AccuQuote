import SwiftUI

// MARK: - Design tokens

/// Central palette/type-scale namespace — kept as static constants rather
/// than a SwiftUI Environment value so every view can reach colors/fonts
/// without threading a theme object through the whole hierarchy.
enum AQ {
    // Palette
    static let ink       = Color(red: 0.07, green: 0.07, blue: 0.09)      // near-black
    static let label     = Color(red: 0.18, green: 0.18, blue: 0.22)
    static let secondary = Color(red: 0.52, green: 0.52, blue: 0.56)
    static let rule      = Color(red: 0.88, green: 0.88, blue: 0.91)
    static let fill      = Color(red: 0.96, green: 0.96, blue: 0.97)
    static let blue      = Color(red: 0.00, green: 0.48, blue: 1.00)      // iOS system blue
    static let green     = Color(red: 0.13, green: 0.72, blue: 0.43)
    static let amber     = Color(red: 1.00, green: 0.80, blue: 0.00)

    // Type
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }
    static func title(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .default)
    }
    static func body(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }
    static func caption(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .default)
    }
    static func mono(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
}

// MARK: - Logo component
// "AppLogo" is the exact same 1024×1024 PNG used as the app icon (Assets.xcassets/
// AppIcon.appiconset/icon-1024.png, duplicated into AppLogo.imageset) — the icon
// shown throughout the app must be pixel-identical to the App Store icon, not a
// separate approximation like an SF Symbol.

struct AQLogoView: View {
    var height: CGFloat = 22
    var body: some View {
        HStack(spacing: height * 0.28) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: height * 0.8, height: height * 0.8)
                .clipShape(RoundedRectangle(cornerRadius: height * 0.8 * 0.2))
            Text("AccuQuote")
                .font(.system(size: height * 0.68, weight: .semibold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, height * 0.4)
        .padding(.vertical, height * 0.18)
        .background(Color(red: 0.06, green: 0.07, blue: 0.13))
        .clipShape(RoundedRectangle(cornerRadius: height * 0.3))
    }
}

// Threshold for the ProfileGateView unlock indicator (used in OnboardingSheet)
let profileUnlockThreshold = 70
