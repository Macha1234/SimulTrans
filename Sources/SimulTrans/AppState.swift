import SwiftUI
import Translation

@Observable
@MainActor
final class AppState {
    struct SupportedLanguage: Identifiable {
        let id: String
        let name: String

        var locale: Locale.Language {
            .init(identifier: id)
        }
    }

    static let supportedLanguages: [SupportedLanguage] = [
        .init(id: "en-US", name: "英語（米国）"),
        .init(id: "en-GB", name: "英語（英国）"),
        .init(id: "ja", name: "日本語"),
        .init(id: "zh-Hans", name: "中国語（簡体字）"),
        .init(id: "zh-Hant", name: "中国語（繁体字）"),
        .init(id: "ko", name: "韓国語"),
        .init(id: "es", name: "スペイン語"),
        .init(id: "fr", name: "フランス語"),
        .init(id: "de", name: "ドイツ語"),
        .init(id: "pt-BR", name: "ポルトガル語（ブラジル）"),
        .init(id: "it", name: "イタリア語"),
        .init(id: "ru", name: "ロシア語"),
        .init(id: "ar", name: "アラビア語"),
    ]

    private static let defaultSourceLanguageIdentifier = "en-US"
    private static let fallbackTargetLanguageIdentifier = "ja"

    // MARK: - Settings
    var sourceLanguage: Locale.Language
    var targetLanguage: Locale.Language
    var overlayOpacity: Double = 0.85
    var fontSize: CGFloat = 16
    var audioSource: AudioSource = .system

    enum AudioSource: String, CaseIterable {
        case system = "システム音声"
        case microphone = "マイク"
    }

    // MARK: - Runtime State
    var isRunning: Bool = false
    var currentOriginalText: String = ""
    var currentTranslatedText: String = ""
    var transcriptEntries: [TranscriptEntry] = []
    var errorMessage: String?

    // MARK: - Translation Session (set by .translationTask)
    var translationSession: TranslationSession?
    var translationConfig: TranslationSession.Configuration?

    // MARK: - Max History
    private let maxEntries = 200

    init() {
        sourceLanguage = .init(identifier: Self.defaultSourceLanguageIdentifier)
        targetLanguage = .init(identifier: Self.defaultTargetLanguageIdentifier())
        updateTranslationConfig()
    }

    @discardableResult
    func appendEntry(original: String, translated: String?) -> Int {
        let entry = TranscriptEntry(originalText: original, translatedText: translated)
        transcriptEntries.append(entry)
        if transcriptEntries.count > maxEntries {
            transcriptEntries.removeFirst(transcriptEntries.count - maxEntries)
        }
        return transcriptEntries.count - 1
    }

    func updateTranslationConfig() {
        translationConfig = .init(source: sourceLanguage, target: targetLanguage)
    }

    private static func defaultTargetLanguageIdentifier() -> String {
        for preferredLanguage in Locale.preferredLanguages {
            if let matchedIdentifier = matchedSupportedLanguageIdentifier(for: preferredLanguage) {
                return matchedIdentifier
            }
        }
        return fallbackTargetLanguageIdentifier
    }

    private static func matchedSupportedLanguageIdentifier(for preferredIdentifier: String) -> String? {
        let normalized = preferredIdentifier
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()

        if let exactMatch = supportedLanguages.first(where: { $0.id.lowercased() == normalized }) {
            return exactMatch.id
        }

        if normalized.hasPrefix("en-gb") { return "en-GB" }
        if normalized.hasPrefix("en") { return "en-US" }
        if normalized.hasPrefix("ja") { return "ja" }
        if normalized.hasPrefix("zh-hant") || normalized.hasPrefix("zh-tw") || normalized.hasPrefix("zh-hk") || normalized.hasPrefix("zh-mo") {
            return "zh-Hant"
        }
        if normalized.hasPrefix("zh") { return "zh-Hans" }
        if normalized.hasPrefix("ko") { return "ko" }
        if normalized.hasPrefix("es") { return "es" }
        if normalized.hasPrefix("fr") { return "fr" }
        if normalized.hasPrefix("de") { return "de" }
        if normalized.hasPrefix("pt") { return "pt-BR" }
        if normalized.hasPrefix("it") { return "it" }
        if normalized.hasPrefix("ru") { return "ru" }
        if normalized.hasPrefix("ar") { return "ar" }

        return nil
    }
}
