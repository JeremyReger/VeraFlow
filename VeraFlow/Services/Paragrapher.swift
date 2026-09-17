import Foundation

/// A paragraph built from timed words before speaker labels exist (SPEC §9.3).
struct ProvisionalSegment: Equatable, Sendable {
    var start: TimeInterval
    var end: TimeInterval
    var words: [TimedWord]

    var text: String { words.map(\.text).joined(separator: " ") }
}

/// Splits a word stream into provisional paragraphs. Diarization re-splits by speaker later.
enum Paragrapher {
    struct Rules: Sendable {
        /// A silence longer than this starts a new paragraph.
        var maxGap: TimeInterval = 1.2
        /// After a sentence ends, break if the paragraph already has more words than this.
        var sentenceWordLimit = 25
        /// Never let a paragraph run longer than this.
        var maxDuration: TimeInterval = 45

        static let spec = Rules()
    }

    static func segments(from words: [TimedWord], rules: Rules = .spec) -> [ProvisionalSegment] {
        var result: [ProvisionalSegment] = []
        var current: [TimedWord] = []

        func flush() {
            guard let first = current.first, let last = current.last else { return }
            result.append(ProvisionalSegment(start: first.start, end: last.end, words: current))
            current = []
        }

        for word in words {
            if let first = current.first, let last = current.last {
                let gap = word.start - last.end
                let wouldRunLong = word.end - first.start > rules.maxDuration
                if gap > rules.maxGap || wouldRunLong {
                    flush()
                }
            }
            current.append(word)
            if endsSentence(word.text), current.count > rules.sentenceWordLimit {
                flush()
            }
        }
        flush()
        return result
    }

    /// True for words that close a sentence, ignoring trailing quotes or brackets.
    static func endsSentence(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"'”’)]}"))
        guard let last = trimmed.last else { return false }
        return ".?!".contains(last)
    }
}
