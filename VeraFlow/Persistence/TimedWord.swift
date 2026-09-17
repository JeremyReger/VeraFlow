import Foundation

/// One transcribed word with its audio time range (SPEC §7). Stored encoded in `TranscriptSegment.wordsData`.
struct TimedWord: Codable, Sendable, Equatable {
    var text: String
    var start: TimeInterval
    var end: TimeInterval

    init(text: String, start: TimeInterval, end: TimeInterval) {
        self.text = text
        self.start = start
        self.end = end
    }
}

extension [TimedWord] {
    /// Encodes the words for storage on a `TranscriptSegment`.
    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    /// Decodes words stored on a `TranscriptSegment`. `nil` data decodes to an empty array.
    static func decoded(from data: Data?) throws -> [TimedWord] {
        guard let data else { return [] }
        return try JSONDecoder().decode([TimedWord].self, from: data)
    }
}
