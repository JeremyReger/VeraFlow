import Foundation

public struct SummarizationProgress: Sendable {
    public var completedChunks: Int
    public var totalChunks: Int
    public var currentPhase: String
    
    public init(completedChunks: Int, totalChunks: Int, currentPhase: String) {
        self.completedChunks = completedChunks
        self.totalChunks = totalChunks
        self.currentPhase = currentPhase
    }
}

public protocol SummarizationServiceProtocol: Sendable {
    func isAvailable() async -> Bool
    func generateSummary(
        for segments: [TranscriptSegment],
        template: TemplateID,
        recordingDate: Date,
        progress: (@Sendable (SummarizationProgress) -> Void)?
    ) async throws -> SummaryRecord
}
