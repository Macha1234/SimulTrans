import CoreText
import Foundation

@MainActor
enum AppFontRegistry {
    private static var didRegister = false

    static func registerBundledFonts() {
        guard !didRegister else { return }
        guard let fontsDirectory = Bundle.module.resourceURL?.appendingPathComponent("Fonts", isDirectory: true) else {
            return
        }

        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(
            at: fontsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for url in urls where ["ttf", "otf"].contains(url.pathExtension.lowercased()) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }

        didRegister = true
    }
}
