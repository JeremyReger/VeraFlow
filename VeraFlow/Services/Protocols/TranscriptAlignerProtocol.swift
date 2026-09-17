import Foundation

public struct AlignedSegment: Sendable, Hashable {
    public var index: Int
    public var start: TimeInterval
    public var end: TimeInterval
    public var text: String
    public var speakerKey: String?
    public var words: [TimedWord]
    
    public init(
        index: Int,
        start: TimeInterval,
        end: TimeInterval,
        text: String,
        speakerKey: String? = nil,
        words: [TimedWord] = []
    ) {
        self.index = index
        self.start = start
        self.end = end
        self.text = text
        self.speakerKey = speakerKey
        self.words = words
    }
}

public struct AlignedSpeaker: Sendable, Hashable {
    public var key: String
    public var displayName: String
    public var colorIndex: Int
    
    public init(key: String, displayName: String, colorIndex: Int = 0) {
        self.key = key
        self.displayName = displayName
        self.colorIndex = colorIndex
    }
}

public struct AlignmentResult: Sendable {
    public var segments: [AlignedSegment]
    public var speakers: [AlignedSpeaker]
    
    public init(segments: [AlignedSegment], speakers: [AlignedSpeaker]) {
        self.segments = segments
        self.speakers = speakers
    }
}

public protocol TranscriptAlignerProtocol: Sendable {
    func align(words: [TimedWord], turns: [SpeakerTurn]) -> AlignmentResult
}
