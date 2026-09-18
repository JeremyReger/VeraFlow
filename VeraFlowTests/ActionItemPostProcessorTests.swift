import Foundation
import Testing
@testable import VeraFlow

struct ActionItemPostProcessorTests {
    private let processor = ActionItemPostProcessor(dueDates: FakeDueDateResolver(), calendar: Calendar(identifier: .gregorian))
    private let recordedAt = Date(timeIntervalSince1970: 1_789_000_000)

    private var context: ActionItemPostProcessor.Context {
        ActionItemPostProcessor.Context(
            recordedAt: recordedAt,
            duration: 600,
            speakers: [("S1", "Jeremy"), ("S2", "Speaker 2")],
            segments: [
                (0, "We need the permit before we pour the footer."),
                (216, "I will call the county on Monday about the permit."),
            ]
        )
    }

    @Test("Near-duplicate tasks merge, keeping the longer text, the earliest time, and the known owner")
    func dedupe() {
        let items = processor.process([
            ActionItemDraft(task: "Call county about permit", owner: "", dueText: "", timestamp: "04:00"),
            ActionItemDraft(task: "Call the county about the permit", owner: "Speaker 2", dueText: "tomorrow", timestamp: "03:36"),
            ActionItemDraft(task: "Order the drywall", owner: "Speaker 2", dueText: "", timestamp: "05:00"),
            ActionItemDraft(task: "   ", owner: "", dueText: "", timestamp: ""),
        ], context: context)
        #expect(items.map(\.task) == ["Call the county about the permit", "Order the drywall"])
        #expect(items[0].timestamp == 216)
        #expect(items[0].owner == "Speaker 2")
        #expect(items[0].ownerSpeakerKey == "S2")
        #expect(items[0].dueText == "tomorrow")
        #expect(items[0].dueDate == Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: recordedAt))
        #expect(items[1].dueDate == nil)
    }

    @Test("Links and markdown in model-written task text are stripped before it can reach Reminders")
    func stripsLinks() {
        let items = processor.process([
            ActionItemDraft(task: "**Pay** the deposit at https://evil.example/pay", owner: "[Jeremy](http://x)", dueText: "", timestamp: "01:00"),
        ], context: context)
        #expect(items.count == 1)
        #expect(items.first?.task == "Pay the deposit at")
        #expect(items.first?.owner == "Jeremy")
        #expect(items.first?.ownerSpeakerKey == "S1")
    }

    @Test("Same task with two different named owners stays as two items")
    func differentOwnersKept() {
        let items = processor.process([
            ActionItemDraft(task: "Send the invoice", owner: "Jeremy", dueText: "", timestamp: "01:00"),
            ActionItemDraft(task: "Send the invoice", owner: "Speaker 2", dueText: "", timestamp: "02:00"),
        ], context: context)
        #expect(items.count == 2)
        #expect(items.map(\.ownerSpeakerKey) == ["S1", "S2"])
    }

    @Test("Owners map to speaker keys by label or renamed display name; unknown owners stay free text")
    func owners() {
        let speakers: [(key: String, displayName: String)] = [("S1", "Jeremy"), ("S2", "Speaker 2")]
        #expect(ActionItemPostProcessor.speakerKey(for: "Speaker 2", speakers: speakers) == "S2")
        #expect(ActionItemPostProcessor.speakerKey(for: "speaker 1", speakers: speakers) == "S1")
        #expect(ActionItemPostProcessor.speakerKey(for: "jeremy", speakers: speakers) == "S1")
        #expect(ActionItemPostProcessor.speakerKey(for: "Speaker 7", speakers: speakers) == nil)
        #expect(ActionItemPostProcessor.speakerKey(for: "the plumber", speakers: speakers) == nil)
        #expect(ActionItemPostProcessor.speakerKey(for: "", speakers: speakers) == nil)
    }

    @Test("Timestamps parse, clamp to the duration, or fall back to the paragraph that says the task")
    func timestamps() {
        #expect(ActionItemPostProcessor.parseTimestamp("12:34") == 754)
        #expect(ActionItemPostProcessor.parseTimestamp("[1:02:03]") == 3_723)
        #expect(ActionItemPostProcessor.parseTimestamp("later") == nil)
        #expect(ActionItemPostProcessor.parseTimestamp("12:99") == nil)
        #expect(ActionItemPostProcessor.parseTimestamp("") == nil)

        let items = processor.process([
            ActionItemDraft(task: "Pour the footer", owner: "", dueText: "", timestamp: "99:00"),
            ActionItemDraft(task: "Call the county about the permit", owner: "", dueText: "", timestamp: "sometime"),
            ActionItemDraft(task: "Buy paint", owner: "", dueText: "", timestamp: ""),
        ], context: context)
        #expect(items[0].timestamp == 600, "clamped to the recording length")
        #expect(items[1].timestamp == 216, "three shared words with the second paragraph")
        #expect(items[2].timestamp == nil)
    }

    @Test("Similarity ignores case, punctuation, and stopwords")
    func similarity() {
        let a = ActionItemPostProcessor.normalizedTokens("Call the County about the permit!")
        let b = ActionItemPostProcessor.normalizedTokens("call county, permit")
        #expect(a == ["call", "county", "permit"])
        #expect(ActionItemPostProcessor.similarity(a, b) == 1)
        #expect(ActionItemPostProcessor.similarity(a, ["order", "drywall"]) == 0)
        #expect(ActionItemPostProcessor.similarity([], []) == 1)
    }
}
