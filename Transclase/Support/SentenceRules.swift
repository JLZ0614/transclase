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

    /// Sentences longer than this are flushed even without a boundary, so the
    /// reader never waits through a whole monologue.
    static func tooLong(_ text: String) -> Bool {
        text.count > 220
    }
}
