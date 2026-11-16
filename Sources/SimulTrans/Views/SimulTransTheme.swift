import AppKit
import SwiftUI

enum STTheme {
    // MARK: - Raw palettes

    enum Light {
        static let bg       = NSColor(srgbRed: 237 / 255, green: 242 / 255, blue: 250 / 255, alpha: 1)
        static let panel    = NSColor(srgbRed: 250 / 255, green: 252 / 255, blue: 255 / 255, alpha: 1)
        static let panelAlt = NSColor(srgbRed: 227 / 255, green: 234 / 255, blue: 246 / 255, alpha: 1)
        static let ink      = NSColor(srgbRed: 23 / 255, green: 33 / 255, blue: 52 / 255, alpha: 1)
        static let accent   = NSColor(srgbRed: 48 / 255, green: 100 / 255, blue: 222 / 255, alpha: 1)
        static let green    = NSColor(srgbRed: 23 / 255, green: 130 / 255, blue: 98 / 255, alpha: 1)
    }

    enum Dark {
        static let bg       = NSColor(srgbRed: 17 / 255, green: 22 / 255, blue: 33 / 255, alpha: 1)
        static let panel    = NSColor(srgbRed: 30 / 255, green: 37 / 255, blue: 51 / 255, alpha: 1)
        static let panelAlt = NSColor(srgbRed: 40 / 255, green: 49 / 255, blue: 66 / 255, alpha: 1)
        static let ink      = NSColor(srgbRed: 242 / 255, green: 246 / 255, blue: 255 / 255, alpha: 1)
        static let accent   = NSColor(srgbRed: 120 / 255, green: 162 / 255, blue: 255 / 255, alpha: 1)
        static let green    = NSColor(srgbRed: 100 / 255, green: 221 / 255, blue: 181 / 255, alpha: 1)
    }

    // MARK: - Adaptive tokens

    static let bg       = adaptive(light: Light.bg,       dark: Dark.bg)
    static let panel    = adaptive(light: Light.panel,    dark: Dark.panel)
    static let panelAlt = adaptive(light: Light.panelAlt, dark: Dark.panelAlt)
    static let ink      = adaptive(light: Light.ink,      dark: Dark.ink)
    static let accent   = adaptive(light: Light.accent,   dark: Dark.accent)
    static let green    = adaptive(light: Light.green,    dark: Dark.green)

    static let inkSecondary = adaptive(light: Light.ink.withAlphaComponent(0.72),
                                       dark:  Dark.ink.withAlphaComponent(0.76))
    static let inkTertiary  = adaptive(light: Light.ink.withAlphaComponent(0.58),
                                       dark:  Dark.ink.withAlphaComponent(0.58))
    static let rule         = adaptive(light: Light.ink.withAlphaComponent(0.10),
                                       dark:  Dark.ink.withAlphaComponent(0.10))
    static let ruleHard     = adaptive(light: Light.ink.withAlphaComponent(0.18),
                                       dark:  Dark.ink.withAlphaComponent(0.18))
    static let accentSoft   = adaptive(light: Light.accent.withAlphaComponent(0.12),
                                       dark:  Dark.accent.withAlphaComponent(0.18))

    static let shadow = Color.black.opacity(0.08)

    // Foreground used on top of `accent` (always near-white paper tone)
    static let onAccent = Color.white

    // MARK: - Semantic product tokens

    static let windowBackground = bg
    static let cardBackground = panel
    static let controlBackground = panelAlt
    static let primaryLabel = ink
    static let secondaryLabel = inkSecondary
    static let tertiaryLabel = inkTertiary
    static let separator = rule
    static let strongSeparator = ruleHard
    static let liveStatus = green
    static let danger = adaptive(
        light: NSColor(srgbRed: 202 / 255, green: 73 / 255, blue: 73 / 255, alpha: 1),
        dark: NSColor(srgbRed: 240 / 255, green: 113 / 255, blue: 113 / 255, alpha: 1)
    )
    static let overlayBackground = Color(.sRGB, red: 11 / 255, green: 13 / 255, blue: 16 / 255, opacity: 1)
    static let overlayPrimary = Color.white.opacity(0.96)
    static let overlaySecondary = Color.white.opacity(0.78)
    static let overlayTertiary = Color.white.opacity(0.60)
    static let overlayRule = Color.white.opacity(0.10)

    static let controlWindowSize = CGSize(width: 480, height: 760)
    static let controlWindowMinSize = CGSize(width: 440, height: 640)
    static let overlayWindowSize = CGSize(width: 760, height: 300)
    static let overlayMinSize = CGSize(width: 480, height: 200)
    static let settingsWindowSize = CGSize(width: 900, height: 700)

    // MARK: - Shared glass and typography tokens

    static let glassBorder = adaptive(light: NSColor.white.withAlphaComponent(0.80),
                                      dark: NSColor.white.withAlphaComponent(0.16))
    static let surfaceHighlight = adaptive(light: NSColor.white.withAlphaComponent(0.56),
                                           dark: NSColor.white.withAlphaComponent(0.065))
    static let glassTint = adaptive(light: Light.panel.withAlphaComponent(0.56),
                                    dark: Dark.bg.withAlphaComponent(0.30))
    static let accentGradient = LinearGradient(
        colors: [Color(.sRGB, red: 0.27, green: 0.49, blue: 0.98, opacity: 1),
                 Color(.sRGB, red: 0.20, green: 0.35, blue: 0.86, opacity: 1)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static func displayFont(size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func displayItalicFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func bodyFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func monoFont(size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // MARK: - Helpers

    /// Build a `Color` that resolves against the surrounding `NSAppearance`,
    /// so SwiftUI views automatically swap palettes when the window appearance
    /// changes (system, or via `AppState.appearancePreference`).
    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        let dynamic = NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? dark : light
        }
        return Color(nsColor: dynamic)
    }
}

// MARK: - Shared surfaces

struct STWindowBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            if reduceTransparency {
                STTheme.windowBackground
            } else {
                STVisualEffectMaterial(material: .underWindowBackground)
                STTheme.glassTint
                LinearGradient(colors: [STTheme.accent.opacity(0.075), .clear,
                                        STTheme.liveStatus.opacity(0.035)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct STVisualEffectMaterial: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

struct STGlassSurface: View {
    var radius: CGFloat = 20
    var accented = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            if reduceTransparency {
                shape.fill(STTheme.cardBackground)
            } else {
                shape.fill(.ultraThinMaterial)
                shape.fill(STTheme.cardBackground.opacity(0.28))
                shape.fill(LinearGradient(colors: [STTheme.surfaceHighlight, .clear],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            if accented { shape.fill(STTheme.accent.opacity(0.055)) }
            shape.strokeBorder(STTheme.glassBorder, lineWidth: 0.75)
            if accented { shape.strokeBorder(STTheme.accent.opacity(0.18), lineWidth: 0.75) }
        }
        .shadow(color: STTheme.shadow, radius: 16, x: 0, y: 6)
        .allowsHitTesting(false)
    }
}

struct STIconBadge: View {
    let systemName: String
    var color: Color = STTheme.accent
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.43, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.11), in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                .strokeBorder(color.opacity(0.12), lineWidth: 0.75))
            .accessibilityHidden(true)
    }
}

struct STBrandMark: View {
    var compact = false

    @MainActor private static let logoImage: NSImage = {
        if let url = Bundle.module.url(forResource: "AppLogo", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(systemSymbolName: "waveform", accessibilityDescription: nil) ?? NSImage()
    }()

    var body: some View {
        HStack(spacing: compact ? 8 : 10) {
            Image(nsImage: Self.logoImage)
                .renderingMode(.original)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: compact ? 36 : 44, height: compact ? 36 : 44)
                .accessibilityHidden(true)
            Text("SimulTrans")
                .font(STTheme.displayFont(size: compact ? 17 : 22, weight: .semibold))
                .tracking(-0.7)
                .foregroundStyle(STTheme.primaryLabel)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

enum STButtonVariant { case primary, secondary, quiet, destructive }

/// Keep the native slider's keyboard and accessibility behavior without dense tick marks.
struct STSmoothSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        Slider(value: $value, in: range) { editing in
            if !editing {
                let steps = ((value - range.lowerBound) / step).rounded()
                value = min(range.upperBound, max(range.lowerBound, range.lowerBound + steps * step))
            }
        }
        .tint(STTheme.accent)
    }
}

struct STButtonStyle: ButtonStyle {
    let variant: STButtonVariant
    var compact: Bool

    init(_ variant: STButtonVariant = .secondary, compact: Bool = false) {
        self.variant = variant
        self.compact = compact
    }

    func makeBody(configuration: Configuration) -> some View {
        STButtonBody(configuration: configuration, variant: variant, compact: compact)
    }
}

private struct STButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let variant: STButtonVariant
    let compact: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    private var filled: Bool { variant == .primary || variant == .destructive }

    var body: some View {
        configuration.label
            .font(.system(size: compact ? 12 : 13, weight: .semibold))
            .foregroundStyle(filled ? STTheme.onAccent : STTheme.primaryLabel)
            .padding(.horizontal, compact ? 10 : 14)
            .padding(.vertical, compact ? 7 : 11)
            .frame(minHeight: compact ? 32 : 44)
            .background {
                let shape = RoundedRectangle(cornerRadius: compact ? 10 : 13, style: .continuous)
                ZStack {
                    switch variant {
                    case .primary: shape.fill(STTheme.accentGradient)
                    case .destructive: shape.fill(STTheme.danger)
                    case .secondary: shape.fill(STTheme.controlBackground.opacity(0.62))
                    case .quiet: shape.fill(Color.clear)
                    }
                    shape.fill(Color.white.opacity(configuration.isPressed ? 0.12 : (hovering ? 0.08 : 0)))
                    if variant != .quiet {
                        shape.strokeBorder(filled ? Color.white.opacity(0.20) : STTheme.glassBorder, lineWidth: 0.75)
                    }
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: compact ? 10 : 13, style: .continuous))
            .shadow(color: filled ? STTheme.accent.opacity(hovering ? 0.21 : 0.12) : .clear,
                    radius: 9, y: 3)
            .opacity(isEnabled ? 1 : 0.42)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovering)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
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
