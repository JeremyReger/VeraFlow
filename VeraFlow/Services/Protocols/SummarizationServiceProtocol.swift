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

public struct SummarizationResult: Sendable {
    public var templateID: TemplateID
    public var payloadJSON: Data
    public var actionItems: [ActionItem]
    public var modelInfo: String
    
    public init(
        templateID: TemplateID,
        payloadJSON: Data,
        actionItems: [ActionItem],
        modelInfo: String
    ) {
        self.templateID = templateID
        self.payloadJSON = payloadJSON
        self.actionItems = actionItems
        self.modelInfo = modelInfo
    }
}

public protocol SummarizationServiceProtocol: Sendable {
    func isAvailable() async -> Bool
    
    func generateSummary(
        for segments: [AlignedSegment],
        speakers: [AlignedSpeaker],
        recordingDuration: TimeInterval,
        template: TemplateID,
        recordingDate: Date,
        progress: (@Sendable (SummarizationProgress) -> Void)?
    ) async throws -> SummarizationResult
}

extension SummarizationServiceProtocol {
    @MainActor
    public func generateSummary(
        for segments: [TranscriptSegment],
        speakers: [Speaker],
        recordingDuration: TimeInterval,
        template: TemplateID,
        recordingDate: Date,
        progress: (@Sendable (SummarizationProgress) -> Void)?
    ) async throws -> SummaryRecord {
        let alignedSegments = segments.map {
            AlignedSegment(index: $0.index, start: $0.start, end: $0.end, text: $0.text, speakerKey: $0.speakerKey)
        }
        let alignedSpeakers = speakers.map {
            AlignedSpeaker(key: $0.key, displayName: $0.displayName, colorIndex: $0.colorIndex)
        }
        let result = try await generateSummary(
            for: alignedSegments,
            speakers: alignedSpeakers,
            recordingDuration: recordingDuration,
            template: template,
            recordingDate: recordingDate,
            progress: progress
        )
        let actionsData = (try? JSONEncoder().encode(result.actionItems)) ?? Data()
        return SummaryRecord(
            createdAt: Date(),
            templateID: result.templateID,
            payloadJSON: result.payloadJSON,
            actionItemsState: actionsData,
            modelInfo: result.modelInfo
        )
    }
    
    @MainActor
    public func generateSummary(
        for segments: [TranscriptSegment],
        template: TemplateID,
        recordingDate: Date,
        progress: (@Sendable (SummarizationProgress) -> Void)?
    ) async throws -> SummaryRecord {
        let maxTime = segments.last?.end ?? 0
        return try await generateSummary(
            for: segments,
            speakers: [],
            recordingDuration: maxTime,
            template: template,
            recordingDate: recordingDate,
            progress: progress
        )
    }
}
