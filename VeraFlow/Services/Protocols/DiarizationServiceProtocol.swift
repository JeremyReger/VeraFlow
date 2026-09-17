import Foundation

public struct SpeakerTurn: Sendable, Hashable {
    public var rawSpeakerID: String
    public var start: TimeInterval
    public var end: TimeInterval
    
    public init(rawSpeakerID: String, start: TimeInterval, end: TimeInterval) {
        self.rawSpeakerID = rawSpeakerID
        self.start = start
        self.end = end
    }
}

public protocol DiarizationServiceProtocol: Sendable {
    func isModelReady() async -> Bool
    func prepareModels(progress: (@Sendable (Double) -> Void)?) async throws
    func diarize(audioFileURL: URL, expectedSpeakers: Int?) async throws -> [SpeakerTurn]
}
