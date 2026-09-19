import Foundation

/// One paragraph as the filter sees it: enough to decide whether it shows and how long it is.
struct TranscriptFilterSegment: Equatable, Sendable {
    var index: Int
    var speakerKey: String?
    var start: TimeInterval
    var end: TimeInterval
    var text: String
}

/// Speaker chips plus the search field on the Transcript tab (v1.1 plan item 3; design spec §4
/// Transcript: "a search field and a speaker filter"). Pure, so the chip logic is unit-tested:
/// the speaker narrows which paragraphs are listed, the search highlights matches within them.
struct TranscriptFilter: Equatable, Sendable {
    /// `nil` shows everyone.
    var speakerKey: String?
    var query = ""

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isSearching: Bool { !trimmedQuery.isEmpty }

    var isNarrowing: Bool { speakerKey != nil || isSearching }

    /// Paragraphs that pass the speaker filter, in transcript order.
    func visible(_ segments: [TranscriptFilterSegment]) -> [TranscriptFilterSegment] {
        guard let speakerKey else { return segments }
        return segments.filter { $0.speakerKey == speakerKey }
    }

    /// Indices (into the recording's paragraphs) of visible paragraphs that contain the query.
    func matches(_ segments: [TranscriptFilterSegment]) -> [Int] {
        let shown = visible(segments)
        return TranscriptText.matches(query: query, in: shown.map(\.text)).map { shown[$0].index }
    }

    /// Seconds of speech in the visible paragraphs (a speaker's talk time when one is picked).
    func talkTime(_ segments: [TranscriptFilterSegment]) -> TimeInterval {
        visible(segments).reduce(0) { $0 + max(0, $1.end - $1.start) }
    }

    /// What the header reads next to the field: search matches while searching, otherwise the
    /// picked speaker's paragraph count and talk time ("12 paragraphs · 4:52 of talk time").
    /// Empty when nothing is narrowing the list.
    func countText(_ segments: [TranscriptFilterSegment]) -> String {
        if isSearching {
            let count = matches(segments).count
            return count == 1 ? "1 match" : "\(count) matches"
        }
        guard speakerKey != nil else { return "" }
        let shown = visible(segments)
        let paragraphs = shown.count == 1 ? "1 paragraph" : "\(shown.count) paragraphs"
        return "\(paragraphs) · \(LibraryCardModel.durationText(talkTime(segments))) of talk time"
    }
}
