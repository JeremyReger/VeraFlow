import Foundation
import SwiftData

/// Represents a speaker turn or contiguous paragraph within a transcript (§7)
@Model
public final class TranscriptSegment {
    public var index: Int
    public var start: TimeInterval
    public var end: TimeInterval
    public var text: String
    public var originalText: String
    public var speakerKey: String?
    public var wordsData: Data?
    
    public var words: [TimedWord] {
        get {
            guard let wordsData else { return [] }
            return (try? JSONDecoder().decode([TimedWord].self, from: wordsData)) ?? []
        }
        set {
            wordsData = try? JSONEncoder().encode(newValue)
        }
    }
    
    public init(
        index: Int,
        start: TimeInterval,
        end: TimeInterval,
        text: String,
        originalText: String? = nil,
        speakerKey: String? = nil,
        words: [TimedWord] = []
    ) {
        self.index = index
        self.start = start
        self.end = end
        self.text = text
        self.originalText = originalText ?? text
        self.speakerKey = speakerKey
        self.wordsData = try? JSONEncoder().encode(words)
    }
}
