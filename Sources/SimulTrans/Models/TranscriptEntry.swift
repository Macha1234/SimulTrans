import Foundation

struct TranscriptEntry: Identifiable {
    let id = UUID()
    var originalText: String
    var translatedText: String?
    let timestamp: Date

    init(originalText: String, translatedText: String? = nil) {
        self.originalText = originalText
        self.translatedText = translatedText
        self.timestamp = Date()
    }
}
