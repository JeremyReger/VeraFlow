import Foundation

public final class FakeDiarizationService: DiarizationServiceProtocol, Sendable {
    public init() {}
    
    public func isModelReady() async -> Bool {
        return true
    }
    
    public func prepareModels(progress: (@Sendable (Double) -> Void)?) async throws {
        progress?(1.0)
    }
    
    public func diarize(audioFileURL: URL, expectedSpeakers: Int?) async throws -> [SpeakerTurn] {
        return [
            SpeakerTurn(rawSpeakerID: "SPEAKER_00", start: 0.0, end: 15.0),
            SpeakerTurn(rawSpeakerID: "SPEAKER_01", start: 15.5, end: 32.0)
        ]
    }
}
