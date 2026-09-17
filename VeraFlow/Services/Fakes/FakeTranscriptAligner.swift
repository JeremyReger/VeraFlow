import Foundation

public final class FakeTranscriptAligner: TranscriptAlignerProtocol, Sendable {
    public init() {}
    
    public func align(words: [TimedWord], turns: [SpeakerTurn]) -> AlignmentResult {
        let speaker1 = AlignedSpeaker(key: "S1", displayName: "Speaker 1", colorIndex: 0)
        let speaker2 = AlignedSpeaker(key: "S2", displayName: "Speaker 2", colorIndex: 1)
        
        let segment = AlignedSegment(
            index: 0,
            start: words.first?.start ?? 0,
            end: words.last?.end ?? 10,
            text: words.map(\.text).joined(separator: " "),
            speakerKey: "S1",
            words: words
        )
        
        return AlignmentResult(segments: [segment], speakers: [speaker1, speaker2])
    }
}
