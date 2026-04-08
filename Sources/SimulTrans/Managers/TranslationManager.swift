import Foundation
@preconcurrency import Translation

@MainActor
final class TranslationManager {
    private let debouncer = Debouncer(delay: 0.5)
    var session: TranslationSession?

    var isReady: Bool { session != nil }

    func translate(_ text: String) async throws -> String {
        guard let session else {
            throw TranslationError.noSession
        }
        let response = try await session.translate(text)
        return response.targetText
    }

    /// Translates text with debouncing — only the latest text after 500ms of inactivity is translated.
    func translateDebounced(_ text: String, completion: @escaping @MainActor @Sendable (String) -> Void) {
        let session = self.session
        Task {
            await debouncer.debounce { [session] in
                guard let session else { return }
                if let result = try? await session.translate(text) {
                    await MainActor.run {
                        completion(result.targetText)
                    }
                }
            }
        }
    }
}

enum TranslationError: LocalizedError {
    case noSession

    var errorDescription: String? {
        switch self {
        case .noSession:
            return "翻訳セッションを開始できませんでした。言語設定を確認してください。"
        }
    }
}
