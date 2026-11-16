import Foundation

enum RecognitionEngine: String, CaseIterable, Identifiable, Sendable {
    case appleSpeech
    case whisperLargeV3Turbo
    case qwen3ASR1_7B

    var id: String { rawValue }

    var isLocalASR: Bool {
        switch self {
        case .appleSpeech:
            return false
        case .whisperLargeV3Turbo, .qwen3ASR1_7B:
            return true
        }
    }

    var shortLabel: String {
        switch self {
        case .appleSpeech:
            return "Apple"
        case .whisperLargeV3Turbo:
            return "Whisper"
        case .qwen3ASR1_7B:
            return "Qwen"
        }
    }

    var displayName: String {
        switch self {
        case .appleSpeech:
            return "Apple Speech"
        case .whisperLargeV3Turbo:
            return "Whisper large-v3-turbo"
        case .qwen3ASR1_7B:
            return "Qwen3-ASR-1.7B"
        }
    }

    var setupHint: String {
        switch self {
        case .appleSpeech:
            return "Uses Apple's on-device Speech framework."
        case .whisperLargeV3Turbo:
            return "Requires whisper.cpp server and a ggml large-v3-turbo model."
        case .qwen3ASR1_7B:
            return "Runs Qwen3-ASR-1.7B on the Mini PC GPU through the secure local SSH tunnel."
        }
    }
}
