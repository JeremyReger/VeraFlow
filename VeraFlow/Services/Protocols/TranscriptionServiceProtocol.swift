import Foundation

public struct TranscriptionProgress: Sendable {
    public var fractionCompleted: Double
    public var currentTime: TimeInterval
    public var totalDuration: TimeInterval
    
    public init(fractionCompleted: Double, currentTime: TimeInterval, totalDuration: TimeInterval) {
        self.fractionCompleted = fractionCompleted
        self.currentTime = currentTime
        self.totalDuration = totalDuration
    }
}

public struct ProvisionalSegment: Sendable, Hashable {
    public var index: Int
    public var start: TimeInterval
    public var end: TimeInterval
    public var text: String
    public var words: [TimedWord]
    
    public init(index: Int, start: TimeInterval, end: TimeInterval, text: String, words: [TimedWord]) {
        self.index = index
        self.start = start
        self.end = end
        self.text = text
        self.words = words
    }
}

public struct TranscriptionResult: Sendable {
    public var words: [TimedWord]
    public var segments: [ProvisionalSegment]
    public var engineUsed: String // e.g., "SpeechTranscriber (en-US)" or "DictationTranscriber"
    
    public init(words: [TimedWord], segments: [ProvisionalSegment], engineUsed: String) {
        self.words = words
        self.segments = segments
        self.engineUsed = engineUsed
    }
}

public protocol TranscriptionServiceProtocol: Sendable {
    func isAvailable() async -> Bool
    func checkAndRequestAssets(locale: Locale) async throws -> Bool
    func transcribeAudio(fileURL: URL, locale: Locale, progress: (@Sendable (TranscriptionProgress) -> Void)?) async throws -> TranscriptionResult
}
