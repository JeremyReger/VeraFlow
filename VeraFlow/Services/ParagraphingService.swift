import Foundation

/// Pure Swift paragraphing engine implementing §9.3 boundary rules.
/// Builds provisional segments from timed words prior to speaker diarization.
public final class ParagraphingService: Sendable {
    public static let silenceGapThreshold: TimeInterval = 1.2 // Break on silence > 1.2s
    public static let sentenceWordThreshold: Int = 25          // Break on sentence end + >= 25 words
    public static let maxSegmentDuration: TimeInterval = 45.0 // Break on duration >= 45.0s
    
    public init() {}
    
    public func buildSegments(from words: [TimedWord]) -> [ProvisionalSegment] {
        guard !words.isEmpty else { return [] }
        
        var segments: [ProvisionalSegment] = []
        var currentWords: [TimedWord] = []
        var segmentIndex = 0
        
        for (i, word) in words.enumerated() {
            currentWords.append(word)
            
            let isLastWord = (i == words.count - 1)
            if isLastWord {
                segments.append(makeSegment(index: segmentIndex, words: currentWords))
                break
            }
            
            let nextWord = words[i + 1]
            let gap = nextWord.start - word.end
            let segmentDuration = word.end - (currentWords.first?.start ?? word.start)
            let isSentenceEnd = word.text.hasSuffix(".") || word.text.hasSuffix("?") || word.text.hasSuffix("!")
            
            let shouldBreak = gap > Self.silenceGapThreshold ||
                              (isSentenceEnd && currentWords.count >= Self.sentenceWordThreshold) ||
                              segmentDuration >= Self.maxSegmentDuration
            
            if shouldBreak {
                segments.append(makeSegment(index: segmentIndex, words: currentWords))
                currentWords = []
                segmentIndex += 1
            }
        }
        
        return segments
    }
    
    private func makeSegment(index: Int, words: [TimedWord]) -> ProvisionalSegment {
        let start = words.first?.start ?? 0
        let end = words.last?.end ?? 0
        let text = words.map(\.text).joined(separator: " ")
        return ProvisionalSegment(
            index: index,
            start: start,
            end: end,
            text: text,
            words: words
        )
    }
}
