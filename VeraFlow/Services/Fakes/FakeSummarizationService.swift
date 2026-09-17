import Foundation

public final class FakeSummarizationService: SummarizationServiceProtocol, Sendable {
    public init() {}
    
    public func isAvailable() async -> Bool {
        return true
    }
    
    public func generateSummary(
        for segments: [TranscriptSegment],
        template: TemplateID,
        recordingDate: Date,
        progress: (@Sendable (SummarizationProgress) -> Void)?
    ) async throws -> SummaryRecord {
        progress?(SummarizationProgress(completedChunks: 1, totalChunks: 1, currentPhase: "Synthesizing"))
        
        let actionItem = ActionItem(
            task: "Send revised proposal to client",
            owner: "Speaker 1",
            speakerKey: "S1",
            dueText: "by next Friday",
            resolvedDueDate: Calendar.current.date(byAdding: .day, value: 7, to: recordingDate),
            timestamp: "01:15",
            audioTime: 75.0,
            isCompleted: false
        )
        
        let samplePayload: [String: Any] = [
            "title": "Project Alignment Meeting",
            "overview": "The team reviewed quarterly deliverables and aligned on client milestones.",
            "keyPoints": [
                "Agreed on primary timeline and budget constraints",
                "Reviewed initial architectural draft"
            ],
            "decisions": [
                "Proceed with on-device implementation model"
            ]
        ]
        
        let payloadData = (try? JSONSerialization.data(withJSONObject: samplePayload, options: [])) ?? Data()
        let actionsData = (try? JSONEncoder().encode([actionItem])) ?? Data()
        
        return SummaryRecord(
            createdAt: Date(),
            templateID: template,
            payloadJSON: payloadData,
            actionItemsState: actionsData,
            modelInfo: "FakeSystemLanguageModel"
        )
    }
}
