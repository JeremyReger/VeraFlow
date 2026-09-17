import Foundation

/// A paragraph produced by alignment: contiguous words from one speaker.
struct AlignedSegment: Sendable, Equatable {
    var start: TimeInterval
    var end: TimeInterval
    /// "S1", "S2"… in order of first appearance; `nil` when no speaker turns were supplied.
    var speakerKey: String?
    var words: [TimedWord]

    var text: String {
        words.map(\.text).joined(separator: " ")
    }
}

/// Merges timed words with speaker turns into speaker-labeled segments (SPEC §10.2).
/// Pure Swift, no framework dependencies. `LiveTranscriptAligner` is the real one.
protocol TranscriptAligning: Sendable {
    /// Splits `words` into paragraphs with no speaker information (SPEC §9.3).
    func paragraphs(from words: [TimedWord]) -> [AlignedSegment]
    /// Assigns each word a speaker from `turns`, then builds segments. Empty `turns` behaves like `paragraphs(from:)`.
    func align(words: [TimedWord], turns: [SpeakerTurn]) -> [AlignedSegment]
    /// Labels existing paragraphs (given as their words) without re-splitting them, so a transcript
    /// the user already edited keeps its text. One key per paragraph; `nil` when `turns` is empty.
    func speakerKeys(forSegments segments: [[TimedWord]], turns: [SpeakerTurn]) -> [String?]
}

/// Simplest possible aligner: one segment per turn by word midpoint, or one segment overall.
struct FakeTranscriptAligner: TranscriptAligning {
    func paragraphs(from words: [TimedWord]) -> [AlignedSegment] {
        guard let first = words.first, let last = words.last else { return [] }
        return [AlignedSegment(start: first.start, end: last.end, speakerKey: nil, words: words)]
    }

    func align(words: [TimedWord], turns: [SpeakerTurn]) -> [AlignedSegment] {
        guard !turns.isEmpty else { return paragraphs(from: words) }
        let sortedTurns = turns.sorted { $0.start < $1.start }
        var keyByID: [String: String] = [:]
        for turn in sortedTurns where keyByID[turn.speakerID] == nil {
            keyByID[turn.speakerID] = "S\(keyByID.count + 1)"
        }

        var segments: [AlignedSegment] = []
        for word in words {
            let midpoint = (word.start + word.end) / 2
            let turn = sortedTurns.first { midpoint >= $0.start && midpoint < $0.end } ?? sortedTurns.last!
            let key = keyByID[turn.speakerID]
            if var current = segments.last, current.speakerKey == key {
                current.words.append(word)
                current.end = word.end
                segments[segments.count - 1] = current
            } else {
                segments.append(AlignedSegment(start: word.start, end: word.end, speakerKey: key, words: [word]))
            }
        }
        return segments
    }

    func speakerKeys(forSegments segments: [[TimedWord]], turns: [SpeakerTurn]) -> [String?] {
        guard !turns.isEmpty else { return Array(repeating: nil, count: segments.count) }
        let labeled = align(words: segments.flatMap { $0 }, turns: turns)
        // The fake's segments are one per turn; each paragraph takes the key of its first word.
        var keyByWordStart: [TimeInterval: String] = [:]
        for segment in labeled {
            for word in segment.words where keyByWordStart[word.start] == nil {
                keyByWordStart[word.start] = segment.speakerKey
            }
        }
        return segments.map { words in words.first.flatMap { keyByWordStart[$0.start] } }
    }
}
