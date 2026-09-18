import Foundation
import Testing
@testable import VeraFlow

@MainActor
struct SummarizationInputBuilderTests {
    @Test("Lines carry renamed speaker names and the recording's template and date")
    func buildsInput() {
        let recording = PreviewData.sampleRecording()
        recording.speakers.first { $0.key == "S2" }?.displayName = "Dana"
        let input = SummarizationInput.make(from: recording)
        #expect(input.template == .walkthrough)
        #expect(input.recordedAt == recording.createdAt)
        #expect(input.duration == 7)
        #expect(input.lines.map(\.speakerDisplayName) == ["Speaker 1", "Dana"])
        #expect(input.lines.map(\.speakerKey) == ["S1", "S2"])
        #expect(input.lines.first?.text.hasPrefix("We need the permit") == true)
        #expect(SummarizationInput.make(from: recording, template: .client).template == .client)

        let unlabeled = Recording(title: "x")
        unlabeled.segments = [TranscriptSegment(index: 0, start: 0, end: 1, text: "hello")]
        #expect(SummarizationInput.make(from: unlabeled).lines.first?.speakerDisplayName == "Speaker")
    }

    @Test("Post-processing a payload resolves owners, due dates, and measurement timestamps")
    func postProcessesPayload() {
        let recording = PreviewData.sampleRecording()
        let processor = ActionItemPostProcessor(dueDates: FakeDueDateResolver(), calendar: Calendar(identifier: .gregorian))
        let payload = SummaryPayload.walkthrough(WalkthroughSummary(
            title: "t", location: "", overview: "o",
            areas: [WorkArea(
                name: "Kitchen", tasks: [],
                measurements: [
                    Measurement(item: "north wall", value: "12 ft", timestamp: 99),
                    Measurement(item: "call the county on Monday", value: "", timestamp: nil),
                ],
                materials: []
            )],
            customerRequests: [], issuesFound: [], quoteNotes: [],
            actionItems: [
                ActionItem(task: "Call the county about the permit", owner: "Speaker 2", dueText: "tomorrow", timestamp: 3.6),
                ActionItem(task: "Call county about the permit", owner: "", dueText: "", timestamp: nil),
            ]
        ))
        let processed = payload.postProcessed(with: processor, context: .init(recording: recording))
        #expect(processed.actionItems.count == 1)
        #expect(processed.actionItems.first?.ownerSpeakerKey == "S2")
        #expect(processed.actionItems.first?.timestamp == 4)
        #expect(processed.actionItems.first?.dueDate != nil)
        guard case .walkthrough(let summary) = processed else {
            Issue.record("template changed")
            return
        }
        #expect(summary.areas[0].measurements[0].timestamp == 7, "clamped to the duration")
        let placed = try #require(summary.areas[0].measurements[1].timestamp)
        #expect(abs(placed - 3.6) < 0.001, "placed on the paragraph that says it")
    }
}
