import SwiftUI
import Translation

@Observable
@MainActor
final class AppState {
    struct SupportedLanguage: Identifiable {
        let id: String
        let name: String
        let nativeName: String
        let flag: String

        var locale: Locale.Language {
            .init(identifier: id)
        }
    }

    struct RecognitionDebugEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let phase: String
        let rawText: String
        let effectiveText: String
        let displayedText: String
        let translatedText: String
    }

    static let supportedLanguages: [SupportedLanguage] = [
        .init(id: "en-US",   name: "English (US)",            nativeName: "English (US)",       flag: "🇺🇸"),
        .init(id: "en-GB",   name: "English (UK)",            nativeName: "English (UK)",       flag: "🇬🇧"),
        .init(id: "zh-Hans", name: "Chinese (Simplified)",    nativeName: "简体中文",            flag: "🇨🇳"),
        .init(id: "zh-Hant", name: "Chinese (Traditional)",   nativeName: "繁體中文",            flag: "🇹🇼"),
        .init(id: "ja",      name: "Japanese",                nativeName: "日本語",              flag: "🇯🇵"),
        .init(id: "ko",      name: "Korean",                  nativeName: "한국어",              flag: "🇰🇷"),
        .init(id: "es",      name: "Spanish",                 nativeName: "Español",            flag: "🇪🇸"),
        .init(id: "fr",      name: "French",                  nativeName: "Français",           flag: "🇫🇷"),
        .init(id: "de",      name: "German",                  nativeName: "Deutsch",            flag: "🇩🇪"),
        .init(id: "it",      name: "Italian",                 nativeName: "Italiano",           flag: "🇮🇹"),
        .init(id: "pt-BR",   name: "Portuguese (Brazil)",     nativeName: "Português (Brasil)", flag: "🇧🇷"),
        .init(id: "pt-PT",   name: "Portuguese (Portugal)",   nativeName: "Português (Portugal)", flag: "🇵🇹"),
        .init(id: "ru",      name: "Russian",                 nativeName: "Русский",            flag: "🇷🇺"),
        .init(id: "uk",      name: "Ukrainian",               nativeName: "Українська",         flag: "🇺🇦"),
        .init(id: "pl",      name: "Polish",                  nativeName: "Polski",             flag: "🇵🇱"),
        .init(id: "nl",      name: "Dutch",                   nativeName: "Nederlands",         flag: "🇳🇱"),
        .init(id: "sv",      name: "Swedish",                 nativeName: "Svenska",            flag: "🇸🇪"),
        .init(id: "da",      name: "Danish",                  nativeName: "Dansk",              flag: "🇩🇰"),
        .init(id: "nb",      name: "Norwegian",               nativeName: "Norsk",              flag: "🇳🇴"),
        .init(id: "fi",      name: "Finnish",                 nativeName: "Suomi",              flag: "🇫🇮"),
        .init(id: "cs",      name: "Czech",                   nativeName: "Čeština",            flag: "🇨🇿"),
        .init(id: "hu",      name: "Hungarian",               nativeName: "Magyar",             flag: "🇭🇺"),
        .init(id: "ro",      name: "Romanian",                nativeName: "Română",             flag: "🇷🇴"),
        .init(id: "el",      name: "Greek",                   nativeName: "Ελληνικά",           flag: "🇬🇷"),
        .init(id: "tr",      name: "Turkish",                 nativeName: "Türkçe",             flag: "🇹🇷"),
        .init(id: "ar",      name: "Arabic",                  nativeName: "العربية",            flag: "🇸🇦"),
        .init(id: "he",      name: "Hebrew",                  nativeName: "עברית",              flag: "🇮🇱"),
        .init(id: "hi",      name: "Hindi",                   nativeName: "हिन्दी",              flag: "🇮🇳"),
        .init(id: "th",      name: "Thai",                    nativeName: "ไทย",                flag: "🇹🇭"),
        .init(id: "vi",      name: "Vietnamese",              nativeName: "Tiếng Việt",         flag: "🇻🇳"),
        .init(id: "id",      name: "Indonesian",              nativeName: "Bahasa Indonesia",   flag: "🇮🇩"),
        .init(id: "ms",      name: "Malay",                   nativeName: "Bahasa Melayu",      flag: "🇲🇾"),
    ]

    private static let defaultSourceLanguageIdentifier = "en-US"
    private static let fallbackTargetLanguageIdentifier = "ja"

    // MARK: - Settings
    var sourceLanguage: Locale.Language
    var targetLanguage: Locale.Language
    var overlayOpacity: Double = 0.85
    var fontSize: CGFloat = 16
    var audioSource: AudioSource = .system
    var appearancePreference: AppearancePreference = .auto
    var launchAtLogin: Bool = false
    var showMenuBarIcon: Bool = true
    var hideDockIcon: Bool = false
    var dimOverlayWhenSilent: Bool = true

    enum AudioSource: String, CaseIterable {
        case system = "System Audio"
        case microphone = "Microphone"

        var localizedName: String {
            switch self {
            case .system:     return String(localized: "System Audio", bundle: .module)
            case .microphone: return String(localized: "Microphone",   bundle: .module)
            }
        }
    }

    // MARK: - Runtime State
    var isRunning: Bool = false
    var sessionStartedAt: Date?
    var currentOriginalText: String = ""
    var currentTranslatedText: String = ""
    var transcriptEntries: [TranscriptEntry] = []
    var errorMessage: String?
    var debugPanelExpanded: Bool = false
    var rawRecognitionText: String = ""
    var effectiveRecognitionText: String = ""
    var lastFinalRecognitionText: String = ""
    var recognitionPhase: String = "idle"
    var debugRecognitionEntries: [RecognitionDebugEntry] = []

    // MARK: - Translation Session (set by .translationTask)
    var translationSession: TranslationSession?
    var translationConfig: TranslationSession.Configuration?

    // MARK: - Max History
    private let maxEntries = 200
    private let maxDebugEntries = 24

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

    /// Format an elapsed duration as `mm:ss` (or `h:mm:ss` past one hour).
    static func formatElapsed(from start: Date?, now: Date = Date()) -> String {
        guard let start else { return "00:00" }
        let total = Int(max(0, now.timeIntervalSince(start)))
        let seconds = total % 60
        let minutes = (total / 60) % 60
        let hours = total / 3600
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func resetRecognitionDebug(keepHistory: Bool) {
        rawRecognitionText = ""
        effectiveRecognitionText = ""
        lastFinalRecognitionText = ""
        recognitionPhase = isRunning ? "listening" : "idle"

        if !keepHistory {
            debugRecognitionEntries.removeAll()
        }
    }

    func recordRecognitionDebug(phase: String,
                                rawText: String,
                                effectiveText: String,
                                displayedText: String,
                                translatedText: String) {
        let entry = RecognitionDebugEntry(timestamp: Date(),
                                          phase: phase,
                                          rawText: rawText,
                                          effectiveText: effectiveText,
                                          displayedText: displayedText,
                                          translatedText: translatedText)
        debugRecognitionEntries.insert(entry, at: 0)
        if debugRecognitionEntries.count > maxDebugEntries {
            debugRecognitionEntries.removeLast(debugRecognitionEntries.count - maxDebugEntries)
        }
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
        if normalized.hasPrefix("pt-pt") { return "pt-PT" }
        if normalized.hasPrefix("pt") { return "pt-BR" }
        if normalized.hasPrefix("it") { return "it" }
        if normalized.hasPrefix("ru") { return "ru" }
        if normalized.hasPrefix("uk") { return "uk" }
        if normalized.hasPrefix("pl") { return "pl" }
        if normalized.hasPrefix("nl") { return "nl" }
        if normalized.hasPrefix("sv") { return "sv" }
        if normalized.hasPrefix("da") { return "da" }
        if normalized.hasPrefix("nb") || normalized.hasPrefix("no") { return "nb" }
        if normalized.hasPrefix("fi") { return "fi" }
        if normalized.hasPrefix("cs") { return "cs" }
        if normalized.hasPrefix("hu") { return "hu" }
        if normalized.hasPrefix("ro") { return "ro" }
        if normalized.hasPrefix("el") { return "el" }
        if normalized.hasPrefix("tr") { return "tr" }
        if normalized.hasPrefix("ar") { return "ar" }
        if normalized.hasPrefix("he") || normalized.hasPrefix("iw") { return "he" }
        if normalized.hasPrefix("hi") { return "hi" }
        if normalized.hasPrefix("th") { return "th" }
        if normalized.hasPrefix("vi") { return "vi" }
        if normalized.hasPrefix("id") || normalized.hasPrefix("in") { return "id" }
        if normalized.hasPrefix("ms") { return "ms" }

        return nil
    }
}
