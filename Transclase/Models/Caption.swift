import Foundation

/// One line of the running transcript: source text plus its translation.
///
/// `id` is derived from the audio timecode of the utterance so that repeated
/// (volatile) recognition results for the same span update the *same* row
/// instead of appending duplicates. That is what keeps the caption list from
/// jumping around while the lecturer is still talking.
struct Caption: Identifiable, Equatable, Sendable {
    enum TranslationState: Equatable, Sendable {
        case idle
        case draft
        case pending
        case done
        case failed(String)
    }

    let id: String
    var source: String
    var target: String?
    var isFinal: Bool
    var state: TranslationState
    var start: TimeInterval
    var end: TimeInterval
    var createdAt: Date

    init(
        id: String,
        source: String,
        target: String? = nil,
        isFinal: Bool,
        state: TranslationState = .idle,
        start: TimeInterval,
        end: TimeInterval,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.source = source
        self.target = target
        self.isFinal = isFinal
        self.state = state
        self.start = start
        self.end = end
        self.createdAt = createdAt
    }

    var wordCount: Int {
        source.split(whereSeparator: \.isWhitespace).count
    }

    /// True when there is nothing useful to show on the translation line.
    var isAwaitingTranslation: Bool {
        isFinal && (state == .pending)
    }
}
