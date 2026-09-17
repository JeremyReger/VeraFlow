import Foundation

/// Which paragraph and word the playhead is on (SPEC §4.4 synced highlight).
struct TranscriptPosition: Equatable, Sendable {
    var segmentIndex: Int
    /// Index into that segment's words; `nil` when the time falls between words or the segment
    /// was edited (words no longer match the text).
    var wordIndex: Int?
}

enum TranscriptCursor {
    /// The paragraph whose range contains `time`, or the last one that started before it.
    /// `segments` must be sorted by start. Returns `nil` before the first paragraph.
    static func position(
        at time: TimeInterval,
        starts: [TimeInterval],
        words: (Int) -> [TimedWord],
        wordsAreCurrent: (Int) -> Bool = { _ in true }
    ) -> TranscriptPosition? {
        guard let segmentIndex = lastIndex(where: starts, notAfter: time) else { return nil }
        guard wordsAreCurrent(segmentIndex) else { return TranscriptPosition(segmentIndex: segmentIndex, wordIndex: nil) }
        let segmentWords = words(segmentIndex)
        let wordStarts = segmentWords.map(\.start)
        guard let wordIndex = lastIndex(where: wordStarts, notAfter: time) else {
            return TranscriptPosition(segmentIndex: segmentIndex, wordIndex: nil)
        }
        // Between two words (a pause) nothing is highlighted, but a small tolerance keeps the
        // highlight from flickering on the tiny gaps the recognizer leaves between words.
        let word = segmentWords[wordIndex]
        let isInside = time <= word.end + 0.15
        return TranscriptPosition(segmentIndex: segmentIndex, wordIndex: isInside ? wordIndex : nil)
    }

    /// Binary search: index of the last element `<= value`, or `nil` if none.
    static func lastIndex(where sortedValues: [TimeInterval], notAfter value: TimeInterval) -> Int? {
        var low = 0
        var high = sortedValues.count
        while low < high {
            let mid = (low + high) / 2
            if sortedValues[mid] <= value {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low == 0 ? nil : low - 1
    }
}
