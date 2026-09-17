import Foundation

public final class FakeTranscriptionService: TranscriptionServiceProtocol, Sendable {
    public init() {}
    
    public func isAvailable() async -> Bool {
        return true
    }
    
    public func checkAndRequestAssets(locale: Locale) async throws -> Bool {
        return true
    }
    
    public func transcribeAudio(
        fileURL: URL,
        locale: Locale,
        progress: (@Sendable (TranscriptionProgress) -> Void)?
    ) async throws -> TranscriptionResult {
        progress?(TranscriptionProgress(fractionCompleted: 0.5, currentTime: 30, totalDuration: 60))
        progress?(TranscriptionProgress(fractionCompleted: 1.0, currentTime: 60, totalDuration: 60))
        
        let words = [
            TimedWord(text: "Welcome", start: 0.0, end: 0.5),
            TimedWord(text: "everyone", start: 0.6, end: 1.0),
            TimedWord(text: "to", start: 1.1, end: 1.2),
            TimedWord(text: "the", start: 1.3, end: 1.4),
            TimedWord(text: "planning", start: 1.5, end: 1.9),
            TimedWord(text: "meeting.", start: 2.0, end: 2.5)
        ]
        
        let segment = ProvisionalSegment(
            index: 0,
            start: 0.0,
            end: 2.5,
            text: "Welcome everyone to the planning meeting.",
            words: words
        )
        
        return TranscriptionResult(
            words: words,
            segments: [segment],
            engineUsed: "FakeSpeechTranscriber"
        )
    }
}
