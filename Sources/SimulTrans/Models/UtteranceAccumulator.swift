import Foundation

/// A recognizer may revise a growing audio window. Replace that hypothesis;
/// only join windows when the transport buffer reaches its limit. Transport
/// limits never create a new caption row.
struct UtteranceAccumulator {
    private var committed = ""
    private(set) var text = ""

    mutating func update(_ hypothesis: String, commitsWindow: Bool = false,
                         endsUtterance: Bool = false) -> (text: String, isFinal: Bool) {
        let hypothesis = hypothesis.trimmingCharacters(in: .whitespacesAndNewlines)
        // An empty closing event means silence-only tail, not erase the text.
        if !hypothesis.isEmpty { text = Self.join(committed, hypothesis) }
        let result = (text, endsUtterance)
        if endsUtterance {
            committed = ""
            text = ""
        } else if commitsWindow {
            committed = text
        }
        return result
    }

    static func join(_ left: String, _ right: String) -> String {
        guard !left.isEmpty else { return right }
        guard !right.isEmpty else { return left }
        // At a transport cutoff ASR may invent a full stop after a Japanese
        // case particle (e.g. "何を変えるべきかを。"), despite continuing audio.
        var left = left
        if left.hasSuffix("。") {
            let stem = String(left.dropLast())
            if ["を", "が", "と", "は", "に", "で", "から", "ので", "けれど", "けど"].contains(where: stem.hasSuffix) {
                left = stem
            }
        }
        let space = !isCJK(left.last!) && !isCJK(right.first!) && !".,!?;:，。！？、".contains(right.first!)
        return left + (space ? " " : "") + right
    }

    private static func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains {
            (0x3040...0x30FF).contains($0.value) ||
            (0x3400...0x9FFF).contains($0.value) ||
            (0xAC00...0xD7AF).contains($0.value)
        }
    }
}
