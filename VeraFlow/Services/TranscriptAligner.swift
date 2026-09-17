import Foundation

/// Pure Swift alignment engine (§10.2).
/// Merges timed words and speaker turns using temporal overlap, applies smoothing, and formats speaker-labeled segments.
public final class TranscriptAligner: TranscriptAlignerProtocol, Sendable {
    public static let nearestTurnThreshold: TimeInterval = 0.5 // 0.5s fallback threshold
    
    public init() {}
    
    public func align(words: [TimedWord], turns: [SpeakerTurn]) -> AlignmentResult {
        guard !words.isEmpty else {
            return AlignmentResult(segments: [], speakers: [])
        }
        
        // 1. Assign each word a raw speaker ID (§10.2 #1)
        var wordRawSpeakers: [String] = []
        var lastSpeaker = turns.first?.rawSpeakerID ?? "SPEAKER_00"
        
        for word in words {
            // Find turn with largest temporal overlap
            var bestTurn: SpeakerTurn? = nil
            var maxOverlap: TimeInterval = 0
            
            for turn in turns {
                let overlapStart = max(word.start, turn.start)
                let overlapEnd = min(word.end, turn.end)
                let overlap = overlapEnd - overlapStart
                if overlap > maxOverlap {
                    maxOverlap = overlap
                    bestTurn = turn
                }
            }
            
            if let bestTurn, maxOverlap > 0 {
                wordRawSpeakers.append(bestTurn.rawSpeakerID)
                lastSpeaker = bestTurn.rawSpeakerID
            } else {
                // If no overlap: find nearest turn within 0.5s
                var nearestTurn: SpeakerTurn? = nil
                var minDistance: TimeInterval = Self.nearestTurnThreshold + 0.0001
                
                for turn in turns {
                    let dist: TimeInterval
                    if word.end < turn.start {
                        dist = turn.start - word.end
                    } else if word.start > turn.end {
                        dist = word.start - turn.end
                    } else {
                        dist = 0
                    }
                    if dist < minDistance {
                        minDistance = dist
                        nearestTurn = turn
                    }
                }
                
                if let nearestTurn {
                    wordRawSpeakers.append(nearestTurn.rawSpeakerID)
                    lastSpeaker = nearestTurn.rawSpeakerID
                } else {
                    // Fall back to previous word's speaker
                    wordRawSpeakers.append(lastSpeaker)
                }
            }
        }
        
        // 2. Smooth sandwiched runs of < 3 words (§10.2 #2)
        wordRawSpeakers = smoothSandwichedRuns(wordRawSpeakers)
        
        // 3. Map raw speaker IDs to canonical keys S1...Sn in order of first appearance (§10.2 #4)
        var rawToKeyMap: [String: String] = [:]
        var canonicalSpeakers: [AlignedSpeaker] = []
        var nextSpeakerIndex = 1
        
        for raw in wordRawSpeakers {
            if rawToKeyMap[raw] == nil {
                let key = "S\(nextSpeakerIndex)"
                rawToKeyMap[raw] = key
                canonicalSpeakers.append(AlignedSpeaker(
                    key: key,
                    displayName: "Speaker \(nextSpeakerIndex)",
                    colorIndex: (nextSpeakerIndex - 1) % 6
                ))
                nextSpeakerIndex += 1
            }
        }
        
        // 4. Build segments by speaker turn and §9.3 paragraph rules (§10.2 #3)
        var segments: [AlignedSegment] = []
        var currentSegmentWords: [TimedWord] = []
        var currentSpeakerKey = rawToKeyMap[wordRawSpeakers[0]] ?? "S1"
        var segmentIndex = 0
        
        for i in 0..<words.count {
            let word = words[i]
            let wordKey = rawToKeyMap[wordRawSpeakers[i]] ?? "S1"
            let isSpeakerChange = (wordKey != currentSpeakerKey)
            
            var shouldBreakParagraph = false
            if !currentSegmentWords.isEmpty {
                let prevWord = currentSegmentWords.last!
                let gap = word.start - prevWord.end
                let isSentenceEnd = prevWord.text.hasSuffix(".") || prevWord.text.hasSuffix("?") || prevWord.text.hasSuffix("!")
                let duration = word.end - (currentSegmentWords.first?.start ?? word.start)
                
                shouldBreakParagraph = gap > ParagraphingService.silenceGapThreshold ||
                                      (isSentenceEnd && currentSegmentWords.count >= ParagraphingService.sentenceWordThreshold) ||
                                      duration >= ParagraphingService.maxSegmentDuration
            }
            
            if (isSpeakerChange || shouldBreakParagraph) && !currentSegmentWords.isEmpty {
                segments.append(makeAlignedSegment(
                    index: segmentIndex,
                    speakerKey: currentSpeakerKey,
                    words: currentSegmentWords
                ))
                segmentIndex += 1
                currentSegmentWords = []
                currentSpeakerKey = wordKey
            }
            
            currentSegmentWords.append(word)
            
            if i == words.count - 1 && !currentSegmentWords.isEmpty {
                segments.append(makeAlignedSegment(
                    index: segmentIndex,
                    speakerKey: currentSpeakerKey,
                    words: currentSegmentWords
                ))
            }
        }
        
        return AlignmentResult(segments: segments, speakers: canonicalSpeakers)
    }
    
    // MARK: - Smoothing Helper (§10.2)
    
    private func smoothSandwichedRuns(_ rawSpeakers: [String]) -> [String] {
        var speakers = rawSpeakers
        var changed = true
        var passes = 0
        
        while changed && passes < 8 {
            changed = false
            passes += 1
            var i = 0
            while i < speakers.count {
                let current = speakers[i]
                var runEnd = i
                while runEnd < speakers.count && speakers[runEnd] == current {
                    runEnd += 1
                }
                let runLength = runEnd - i
                
                // If run is fewer than 3 words and sandwiched by the same surrounding speaker
                if runLength < 3 {
                    let hasPrev = (i > 0)
                    let hasNext = (runEnd < speakers.count)
                    if hasPrev && hasNext {
                        let prevSpeaker = speakers[i - 1]
                        let nextSpeaker = speakers[runEnd]
                        if prevSpeaker == nextSpeaker && prevSpeaker != current {
                            for k in i..<runEnd {
                                speakers[k] = prevSpeaker
                            }
                            changed = true
                        }
                    }
                }
                i = runEnd
            }
        }
        return speakers
    }
    
    private func makeAlignedSegment(index: Int, speakerKey: String, words: [TimedWord]) -> AlignedSegment {
        let start = words.first?.start ?? 0
        let end = words.last?.end ?? 0
        let text = words.map(\.text).joined(separator: " ")
        return AlignedSegment(
            index: index,
            start: start,
            end: end,
            text: text,
            speakerKey: speakerKey,
            words: words
        )
    }
}
