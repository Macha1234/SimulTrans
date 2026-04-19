import AppKit
import SwiftUI

enum STTheme {
    // MARK: - Raw palettes

    enum Light {
        static let bg       = NSColor(srgbRed: 244 / 255, green: 239 / 255, blue: 231 / 255, alpha: 1)
        static let panel    = NSColor(srgbRed: 251 / 255, green: 248 / 255, blue: 242 / 255, alpha: 1)
        static let panelAlt = NSColor(srgbRed: 236 / 255, green: 230 / 255, blue: 218 / 255, alpha: 1)
        static let ink      = NSColor(srgbRed: 28 / 255, green: 22 / 255, blue: 18 / 255, alpha: 1)
        static let accent   = NSColor(srgbRed: 199 / 255, green: 87 / 255, blue: 51 / 255, alpha: 1)
        static let green    = NSColor(srgbRed: 92 / 255, green: 141 / 255, blue: 92 / 255, alpha: 1)
    }

    enum Dark {
        static let bg       = NSColor(srgbRed: 26 / 255, green: 22 / 255, blue: 19 / 255, alpha: 1)
        static let panel    = NSColor(srgbRed: 34 / 255, green: 29 / 255, blue: 24 / 255, alpha: 1)
        static let panelAlt = NSColor(srgbRed: 42 / 255, green: 36 / 255, blue: 30 / 255, alpha: 1)
        static let ink      = NSColor(srgbRed: 244 / 255, green: 239 / 255, blue: 231 / 255, alpha: 1)
        static let accent   = NSColor(srgbRed: 217 / 255, green: 122 / 255, blue: 79 / 255, alpha: 1)
        static let green    = NSColor(srgbRed: 132 / 255, green: 178 / 255, blue: 130 / 255, alpha: 1)
    }

    // MARK: - Adaptive tokens

    static let bg       = adaptive(light: Light.bg,       dark: Dark.bg)
    static let panel    = adaptive(light: Light.panel,    dark: Dark.panel)
    static let panelAlt = adaptive(light: Light.panelAlt, dark: Dark.panelAlt)
    static let ink      = adaptive(light: Light.ink,      dark: Dark.ink)
    static let accent   = adaptive(light: Light.accent,   dark: Dark.accent)
    static let green    = adaptive(light: Light.green,    dark: Dark.green)

    static let inkSecondary = adaptive(light: Light.ink.withAlphaComponent(0.65),
                                       dark:  Dark.ink.withAlphaComponent(0.70))
    static let inkTertiary  = adaptive(light: Light.ink.withAlphaComponent(0.42),
                                       dark:  Dark.ink.withAlphaComponent(0.45))
    static let rule         = adaptive(light: Light.ink.withAlphaComponent(0.10),
                                       dark:  Dark.ink.withAlphaComponent(0.10))
    static let ruleHard     = adaptive(light: Light.ink.withAlphaComponent(0.18),
                                       dark:  Dark.ink.withAlphaComponent(0.18))
    static let accentSoft   = adaptive(light: Light.accent.withAlphaComponent(0.12),
                                       dark:  Dark.accent.withAlphaComponent(0.18))

    static let shadow = Color.black.opacity(0.08)

    // Foreground used on top of `accent` (always near-white paper tone)
    static let onAccent = Color(.sRGB, red: 255 / 255, green: 248 / 255, blue: 242 / 255, opacity: 1)

    static let controlWindowSize = CGSize(width: 440, height: 720)
    static let overlayWindowSize = CGSize(width: 720, height: 420)
    static let overlayMinSize = CGSize(width: 560, height: 240)
    static let settingsWindowSize = CGSize(width: 720, height: 520)

    // MARK: - Fonts

    private enum DisplayFace {
        static let regular = "Fraunces-Regular"
        static let medium = "Fraunces-SemiBold"
        static let italic = "Fraunces-Italic"
        static let mediumItalic = "Fraunces-SemiBoldItalic"
    }

    private enum BodyFace {
        static let regular = "WorkSans-Regular"
        static let medium = "WorkSansRoman-Medium"
        static let semibold = "WorkSansRoman-SemiBold"
        static let bold = "WorkSansRoman-Bold"
    }

    private enum MonoFace {
        static let regular = "IBMPlexMono-Regular"
        static let medium = "IBMPlexMono-Medium"
        static let semibold = "IBMPlexMono-SemiBold"
    }

    static func displayFont(size: CGFloat, weight: Font.Weight = .medium) -> Font {
        let name: String
        switch weight {
        case .regular, .light, .thin, .ultraLight:
            name = DisplayFace.regular
        case .bold, .heavy, .black, .semibold:
            name = DisplayFace.medium
        default:
            name = DisplayFace.medium
        }
        return font(named: name, size: size, fallback: .system(size: size, weight: weight, design: .serif))
    }

    static func displayItalicFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black, .semibold, .medium:
            name = DisplayFace.mediumItalic
        default:
            name = DisplayFace.italic
        }
        return font(named: name, size: size, fallback: .system(size: size, weight: weight, design: .serif).italic())
    }

    static func bodyFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black:
            name = BodyFace.bold
        case .semibold:
            name = BodyFace.semibold
        case .medium:
            name = BodyFace.medium
        default:
            name = BodyFace.regular
        }
        return font(named: name, size: size, fallback: .system(size: size, weight: weight))
    }

    static func monoFont(size: CGFloat, weight: Font.Weight = .medium) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black, .semibold:
            name = MonoFace.semibold
        case .medium:
            name = MonoFace.medium
        default:
            name = MonoFace.regular
        }
        return font(named: name, size: size, fallback: .system(size: size, weight: weight, design: .monospaced))
    }

    private static func font(named name: String, size: CGFloat, fallback: Font) -> Font {
        if NSFont(name: name, size: size) != nil {
            return .custom(name, size: size)
        }
        return fallback
    }

    // MARK: - Helpers

    /// Build a `Color` that resolves against the surrounding `NSAppearance`,
    /// so SwiftUI views automatically swap palettes when the window appearance
    /// changes (system, or via `AppState.appearancePreference`).
    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        let dynamic = NSColor(name: nil) { appearance in
            let darkNames: [NSAppearance.Name] = [
                .darkAqua,
                .vibrantDark,
                .accessibilityHighContrastDarkAqua,
                .accessibilityHighContrastVibrantDark,
            ]
            return appearance.bestMatch(from: darkNames) != nil ? dark : light
        }
        return Color(nsColor: dynamic)
    }
}

// MARK: - Appearance preference

enum AppearancePreference: String, CaseIterable, Identifiable {
    case auto
    case light
    case dark

    var id: String { rawValue }

    @MainActor
    func label(in locale: Locale) -> String {
        switch self {
        case .auto:
            return AppState.localizedString("Auto", localizationIdentifier: locale.identifier)
        case .light:
            return AppState.localizedString("Light", localizationIdentifier: locale.identifier)
        case .dark:
            return AppState.localizedString("Dark", localizationIdentifier: locale.identifier)
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .auto:  return nil
        case .light: return .light
        case .dark:  return .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .auto:  return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark:  return NSAppearance(named: .darkAqua)
        }
    }
}
