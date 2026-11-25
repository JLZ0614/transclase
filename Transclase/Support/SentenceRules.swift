import Foundation

/// Decides when a run of recognised fragments forms a complete sentence.
///
/// Apple's translator has no context parameter — the only lever we have is
/// handing it a whole sentence instead of two fragments. The recogniser emits
/// finals at pauses, which is close to but not the same as sentence boundaries.
enum SentenceRules {
    private static let terminals: Set<Character> = [
        ".", "!", "?", "。", "！", "？", "…", "；", ";",
    ]

    /// Punctuation that may trail a sentence without ending it ("…" is handled
    /// above), plus closing quotes/brackets to look through.
    private static let trailing: Set<Character> = [
        "\"", "'", "”", "’", "）", ")", "】", "」", "』", "»",
    ]

    private static let abbreviations: Set<String> = [
        "e.g.", "i.e.", "etc.", "vs.", "mr.", "mrs.", "ms.", "dr.", "prof.",
        "st.", "no.", "fig.", "eq.", "ref.", "al.",
    ]

    static func endsSentence(_ text: String) -> Bool {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = trimmed.last, trailing.contains(last) {
            trimmed.removeLast()
        }
        guard let last = trimmed.last, terminals.contains(last) else { return false }

        let lower = trimmed.lowercased()
        for abbreviation in abbreviations where lower.hasSuffix(abbreviation) {
            return false
        }
        return true
    }

    /// Roughly 20 English words. Longer input measurably degrades Apple's
    /// on-device translation, so segments are kept short on purpose.
    static let maxWords = 20
    /// CJK text has no spaces; count characters instead.
    static let maxCJKCharacters = 42

    static func isSpaced(_ text: String) -> Bool {
        text.contains(" ")
    }

    static func words(in text: String) -> [String] {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .map(String.init)
    }

    static func tooLong(_ text: String) -> Bool {
        if isSpaced(text) {
            return words(in: text).count > maxWords
        }
        return text.count > maxCJKCharacters
    }

    /// Splits an over-long sentence into chunks of at most `maxWords` words,
    /// preferring to end a chunk on punctuation.
    static func chunks(of text: String) -> [String] {
        guard tooLong(text) else { return [text] }

        if isSpaced(text) {
            var out: [String] = []
            var current: [String] = []
            for word in words(in: text) {
                current.append(word)
                let closedByPunctuation = word.last.map { terminals.contains($0) } ?? false
                if current.count >= maxWords || (closedByPunctuation && current.count >= maxWords / 2) {
                    out.append(current.joined(separator: " "))
                    current = []
                }
            }
            if !current.isEmpty { out.append(current.joined(separator: " ")) }
            return out.isEmpty ? [text] : out
        }

        var out: [String] = []
        var buffer = ""
        for character in text {
            buffer.append(character)
            if buffer.count >= maxCJKCharacters || (terminals.contains(character) && buffer.count >= maxCJKCharacters / 2) {
                out.append(buffer)
                buffer = ""
            }
        }
        if !buffer.trimmingCharacters(in: .whitespaces).isEmpty { out.append(buffer) }
        return out.isEmpty ? [text] : out
    }
}
