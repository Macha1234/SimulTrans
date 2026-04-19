import SwiftUI
import Translation

@Observable
@MainActor
final class AppState {
    enum AppDisplayLanguage: String, CaseIterable, Identifiable {
        case system
        case english
        case simplifiedChinese
        case traditionalChinese
        case japanese

        var id: String { rawValue }

        var localizationIdentifier: String? {
            switch self {
            case .system:
                return nil
            case .english:
                return "en"
            case .simplifiedChinese:
                return "zh-Hans"
            case .traditionalChinese:
                return "zh-Hant"
            case .japanese:
                return "ja"
            }
        }
    }

    struct SupportedLanguage: Identifiable {
        let id: String
        let name: String
        let nativeName: String

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
        .init(id: "en-US",   name: "English (US)",            nativeName: "English (US)"),
        .init(id: "en-GB",   name: "English (UK)",            nativeName: "English (UK)"),
        .init(id: "zh-Hans", name: "Chinese (Simplified)",    nativeName: "简体中文"),
        .init(id: "zh-Hant", name: "Chinese (Traditional)",   nativeName: "繁體中文"),
        .init(id: "ja",      name: "Japanese",                nativeName: "日本語"),
        .init(id: "ko",      name: "Korean",                  nativeName: "한국어"),
        .init(id: "es",      name: "Spanish",                 nativeName: "Español"),
        .init(id: "fr",      name: "French",                  nativeName: "Français"),
        .init(id: "de",      name: "German",                  nativeName: "Deutsch"),
        .init(id: "it",      name: "Italian",                 nativeName: "Italiano"),
        .init(id: "pt-BR",   name: "Portuguese (Brazil)",     nativeName: "Português (Brasil)"),
        .init(id: "pt-PT",   name: "Portuguese (Portugal)",   nativeName: "Português (Portugal)"),
        .init(id: "ru",      name: "Russian",                 nativeName: "Русский"),
        .init(id: "uk",      name: "Ukrainian",               nativeName: "Українська"),
        .init(id: "pl",      name: "Polish",                  nativeName: "Polski"),
        .init(id: "nl",      name: "Dutch",                   nativeName: "Nederlands"),
        .init(id: "sv",      name: "Swedish",                 nativeName: "Svenska"),
        .init(id: "da",      name: "Danish",                  nativeName: "Dansk"),
        .init(id: "nb",      name: "Norwegian",               nativeName: "Norsk"),
        .init(id: "fi",      name: "Finnish",                 nativeName: "Suomi"),
        .init(id: "cs",      name: "Czech",                   nativeName: "Čeština"),
        .init(id: "hu",      name: "Hungarian",               nativeName: "Magyar"),
        .init(id: "ro",      name: "Romanian",                nativeName: "Română"),
        .init(id: "el",      name: "Greek",                   nativeName: "Ελληνικά"),
        .init(id: "tr",      name: "Turkish",                 nativeName: "Türkçe"),
        .init(id: "ar",      name: "Arabic",                  nativeName: "العربية"),
        .init(id: "he",      name: "Hebrew",                  nativeName: "עברית"),
        .init(id: "hi",      name: "Hindi",                   nativeName: "हिन्दी"),
        .init(id: "th",      name: "Thai",                    nativeName: "ไทย"),
        .init(id: "vi",      name: "Vietnamese",              nativeName: "Tiếng Việt"),
        .init(id: "id",      name: "Indonesian",              nativeName: "Bahasa Indonesia"),
        .init(id: "ms",      name: "Malay",                   nativeName: "Bahasa Melayu"),
    ]

    private static let defaultSourceLanguageIdentifier = "en-US"
    private static let fallbackTargetLanguageIdentifier = "ja"
    private static let fallbackInterfaceLocalizationIdentifier = "en"
    private static let appDisplayLanguageDefaultsKey = "simultrans.appDisplayLanguage"

    // MARK: - Settings
    var sourceLanguage: Locale.Language {
        didSet { updateTranslationConfig() }
    }
    var targetLanguage: Locale.Language {
        didSet { updateTranslationConfig() }
    }
    var overlayOpacity: Double = 0.85
    var fontSize: CGFloat = 16
    var audioSource: AudioSource = .system
    var appearancePreference: AppearancePreference = .auto
    var launchAtLogin: Bool = false
    var showMenuBarIcon: Bool = true
    var hideDockIcon: Bool = false
    var dimOverlayWhenSilent: Bool = true
    var appDisplayLanguage: AppDisplayLanguage {
        didSet {
            UserDefaults.standard.set(appDisplayLanguage.rawValue, forKey: Self.appDisplayLanguageDefaultsKey)
        }
    }

    enum AudioSource: String, CaseIterable {
        case system = "System Audio"
        case microphone = "Microphone"

        @MainActor
        func localizedName(in locale: Locale) -> String {
            switch self {
            case .system:
                return AppState.localizedString("System Audio", localizationIdentifier: locale.identifier)
            case .microphone:
                return AppState.localizedString("Microphone", localizationIdentifier: locale.identifier)
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

    var systemInterfaceLocale: Locale {
        Locale(identifier: Self.systemInterfaceLocalizationIdentifier())
    }

    var appInterfaceLocale: Locale {
        Locale(identifier: appInterfaceLocalizationIdentifier)
    }

    var appInterfaceLocalizationIdentifier: String {
        appDisplayLanguage.localizationIdentifier ?? Self.systemInterfaceLocalizationIdentifier()
    }

    var overlayInterfaceLocale: Locale {
        Locale(identifier: overlayInterfaceLocalizationIdentifier)
    }

    var overlayInterfaceLocalizationIdentifier: String {
        Self.interfaceLocalizationIdentifier(for: targetLanguage) ?? Self.systemInterfaceLocalizationIdentifier()
    }

    // MARK: - Max History
    private let maxEntries = 200
    private let maxDebugEntries = 24

    init() {
        sourceLanguage = .init(identifier: Self.defaultSourceLanguageIdentifier)
        targetLanguage = .init(identifier: Self.defaultTargetLanguageIdentifier())
        appDisplayLanguage = Self.defaultAppDisplayLanguage()
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

    static func supportedLanguage(for selection: Locale.Language) -> SupportedLanguage? {
        let minimal = selection.minimalIdentifier.lowercased()
        return supportedLanguages.first { language in
            let candidate = language.id.lowercased()
            return candidate == minimal || candidate.hasPrefix("\(minimal)-") || minimal.hasPrefix(candidate)
        }
    }

    static func localizedDisplayName(for selection: Locale.Language, in locale: Locale) -> String {
        let identifier = supportedLanguage(for: selection)?.id ?? selection.minimalIdentifier
        return locale.localizedString(forIdentifier: identifier)
            ?? locale.localizedString(forLanguageCode: selection.minimalIdentifier)
            ?? supportedLanguage(for: selection)?.nativeName
            ?? identifier
    }

    func localizedAppString(_ key: String) -> String {
        Self.localizedString(key, localizationIdentifier: appInterfaceLocalizationIdentifier)
    }

    func localizedOverlayString(_ key: String) -> String {
        Self.localizedString(key, localizationIdentifier: overlayInterfaceLocalizationIdentifier)
    }

    func localizedAppDisplayLanguageName(_ option: AppDisplayLanguage) -> String {
        switch option {
        case .system:
            return localizedAppString("Use system language")
        case .english:
            return appInterfaceLocale.localizedString(forIdentifier: "en") ?? "English"
        case .simplifiedChinese:
            return appInterfaceLocale.localizedString(forIdentifier: "zh-Hans") ?? "Chinese (Simplified)"
        case .traditionalChinese:
            return appInterfaceLocale.localizedString(forIdentifier: "zh-Hant") ?? "Chinese (Traditional)"
        case .japanese:
            return appInterfaceLocale.localizedString(forIdentifier: "ja") ?? "Japanese"
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

    private static func systemInterfaceLocalizationIdentifier() -> String {
        for preferredLanguage in Locale.preferredLanguages {
            if let matchedIdentifier = interfaceLocalizationIdentifier(forPreferredIdentifier: preferredLanguage) {
                return matchedIdentifier
            }
        }
        return fallbackInterfaceLocalizationIdentifier
    }

    private static func interfaceLocalizationIdentifier(for language: Locale.Language) -> String? {
        interfaceLocalizationIdentifier(forPreferredIdentifier: language.maximalIdentifier)
            ?? interfaceLocalizationIdentifier(forPreferredIdentifier: language.minimalIdentifier)
    }

    private static func interfaceLocalizationIdentifier(forPreferredIdentifier preferredIdentifier: String) -> String? {
        let normalized = preferredIdentifier
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()

        if normalized.hasPrefix("zh-hant") || normalized.hasPrefix("zh-tw") || normalized.hasPrefix("zh-hk") || normalized.hasPrefix("zh-mo") {
            return "zh-Hant"
        }
        if normalized.hasPrefix("zh") { return "zh-Hans" }
        if normalized.hasPrefix("ja") { return "ja" }
        if normalized.hasPrefix("en") { return "en" }
        return nil
    }

    private static func defaultAppDisplayLanguage() -> AppDisplayLanguage {
        if let rawValue = UserDefaults.standard.string(forKey: appDisplayLanguageDefaultsKey),
           let savedValue = AppDisplayLanguage(rawValue: rawValue) {
            return savedValue
        }
        return .system
    }

    static func localizedString(_ key: String, localizationIdentifier: String) -> String {
        let normalizedIdentifier = interfaceLocalizationIdentifier(forPreferredIdentifier: localizationIdentifier)
            ?? localizationIdentifier

        guard let path = Bundle.module.path(forResource: normalizedIdentifier, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return NSLocalizedString(key, bundle: .module, comment: "")
        }

        return NSLocalizedString(key, bundle: bundle, comment: "")
    }
}
