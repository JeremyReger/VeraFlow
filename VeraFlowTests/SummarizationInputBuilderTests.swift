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
        let speech = input.lines.filter { !$0.isMark }
        #expect(speech.map(\.speakerDisplayName) == ["Speaker 1", "Dana"])
        #expect(speech.map(\.speakerKey) == ["S1", "S2"])
        #expect(speech.first?.text.hasPrefix("We need the permit") == true)
        #expect(input.lines.filter(\.isMark).map(\.text) == ["Permit question"], "the sample's mark rides along")
        #expect(SummarizationInput.make(from: recording, template: .client).template == .client)

        let unlabeled = Recording(title: "x")
        unlabeled.segments = [TranscriptSegment(index: 0, start: 0, end: 1, text: "hello")]
        #expect(SummarizationInput.make(from: unlabeled).lines.first?.speakerDisplayName == "Speaker")
    }

    @Test("The user's marks are woven in by time; interrupted marks are left out")
    func marksInInput() {
        let recording = PreviewData.sampleRecording()   // paragraphs start at 0 and about 3.6 s
        recording.bookmarks = [
            Bookmark(time: 5, note: "Decision"),
            Bookmark(time: 1, note: nil),
            Bookmark(time: 2, note: Bookmark.interruptedNote, kind: .interrupted),
        ]
        let lines = SummarizationInput.make(from: recording).lines
        #expect(lines.filter(\.isMark).map(\.start) == [1, 5])
        #expect(lines.map(\.isMark) == [false, true, false, true])
        #expect(lines[1].text == "")
        #expect(lines[3].text == "Decision")
        #expect(lines[3].speakerKey == nil)

        let early = SummarizationInput.merge(speech: lines.filter { !$0.isMark }, marks: [.mark(at: 0, label: "Start")])
        #expect(early.first?.isMark == true, "a mark at the very start comes first")
    }

    @Test("Post-processing a payload resolves owners, due dates, and measurement timestamps")
    func postProcessesPayload() throws {
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
