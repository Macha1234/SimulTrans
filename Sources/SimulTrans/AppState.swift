import SwiftUI
import Translation

@Observable
@MainActor
final class AppState {
    // MARK: - Settings
    var sourceLanguage: Locale.Language = .init(identifier: "en-US")
    var targetLanguage: Locale.Language = .init(identifier: "zh-Hans")
    var overlayOpacity: Double = 0.85
    var fontSize: CGFloat = 16
    var audioSource: AudioSource = .system

    enum AudioSource: String, CaseIterable {
        case system = "系统音频"
        case microphone = "麦克风"
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
}
