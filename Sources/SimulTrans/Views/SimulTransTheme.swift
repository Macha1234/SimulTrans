import SwiftUI

enum STTheme {
    static let bg = Color(.sRGB, red: 244 / 255, green: 239 / 255, blue: 231 / 255, opacity: 1)
    static let panel = Color(.sRGB, red: 251 / 255, green: 248 / 255, blue: 242 / 255, opacity: 1)
    static let panelAlt = Color(.sRGB, red: 236 / 255, green: 230 / 255, blue: 218 / 255, opacity: 1)
    static let ink = Color(.sRGB, red: 28 / 255, green: 22 / 255, blue: 18 / 255, opacity: 1)
    static let inkSecondary = ink.opacity(0.65)
    static let inkTertiary = ink.opacity(0.42)
    static let rule = ink.opacity(0.10)
    static let ruleHard = ink.opacity(0.18)
    static let accent = Color(.sRGB, red: 199 / 255, green: 87 / 255, blue: 51 / 255, opacity: 1)
    static let accentSoft = accent.opacity(0.12)
    static let green = Color(.sRGB, red: 92 / 255, green: 141 / 255, blue: 92 / 255, opacity: 1)
    static let shadow = Color.black.opacity(0.08)

    static func displayFont(size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func monoFont(size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
