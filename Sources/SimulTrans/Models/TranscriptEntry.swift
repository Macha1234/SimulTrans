import Foundation

enum TranslationStage: String, Sendable {
    case pending
    case appleDraft
    case contextualAI
}

struct TranscriptEntry: Identifiable {
    let id = UUID()
    var originalText: String
    var translatedText: String?
    var translationStage: TranslationStage
    var translationRequestID: UUID
    let timestamp: Date

    init(originalText: String, translatedText: String? = nil) {
        self.originalText = originalText
        self.translatedText = translatedText
        self.translationStage = translatedText == nil ? .pending : .appleDraft
        self.translationRequestID = UUID()
        self.timestamp = Date()
    }
}
