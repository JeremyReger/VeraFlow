import Foundation

public final class FakeSummarizationService: SummarizationServiceProtocol, Sendable {
    public init() {}
    
    public func isAvailable() async -> Bool {
        return true
    }
    
    public func generateSummary(
        for segments: [AlignedSegment],
        speakers: [AlignedSpeaker],
        recordingDuration: TimeInterval,
        template: TemplateID,
        recordingDate: Date,
        progress: (@Sendable (SummarizationProgress) -> Void)?
    ) async throws -> SummarizationResult {
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
        
        let payloadData: Data
        let encoder = JSONEncoder()
        
        switch template {
        case .general:
            let output = GeneralMeetingOutput(
                overview: "The team reviewed quarterly deliverables and aligned on client milestones.",
                keyDiscussionPoints: [
                    "Agreed on primary timeline and budget constraints",
                    "Reviewed initial architectural draft"
                ],
                decisions: [
                    "Proceed with on-device implementation model"
                ],
                actionItems: [
                    RawActionItem(task: actionItem.task, owner: actionItem.owner, dueText: actionItem.dueText, timestamp: actionItem.timestamp)
                ]
            )
            payloadData = (try? encoder.encode(output)) ?? Data()
            
        case .client:
            let output = ClientConsultingOutput(
                executiveSummary: "Client consultation regarding Q4 deliverables and system requirements.",
                clientNeedsAndGoals: [
                    "Complete migration with zero cloud data exposure",
                    "Maintain sub-second response times"
                ],
                proposedSolutionsAndScope: [
                    "Deploy local SpeechAnalyzer and Foundation Models"
                ],
                commercialsAndTimeline: "Fixed contract with phase-based deliverables by November.",
                actionItems: [
                    RawActionItem(task: actionItem.task, owner: actionItem.owner, dueText: actionItem.dueText, timestamp: actionItem.timestamp)
                ]
            )
            payloadData = (try? encoder.encode(output)) ?? Data()
            
        case .walkthrough:
            let output = ContractorWalkthroughOutput(
                locationAndContext: "Site: 404 Elm Street, Ground Floor Expansion",
                scopeOfWork: [
                    "Framing for 12x14 conference room",
                    "Install 4 recessed LED fixtures"
                ],
                materialsAndEquipment: [
                    "2x4 lumber studs (qty 45)",
                    "1/2-inch drywall sheets (qty 20)"
                ],
                hazardsAndConstraints: [
                    "Main electrical shutoff located in basement",
                    "Restricted parking in rear alley"
                ],
                actionItems: [
                    RawActionItem(task: actionItem.task, owner: actionItem.owner, dueText: actionItem.dueText, timestamp: actionItem.timestamp)
                ]
            )
            payloadData = (try? encoder.encode(output)) ?? Data()
        }
        
        return SummarizationResult(
            templateID: template,
            payloadJSON: payloadData,
            actionItems: [actionItem],
            modelInfo: "FakeSystemLanguageModel"
        )
    }
}
