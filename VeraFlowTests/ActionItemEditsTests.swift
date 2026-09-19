import Foundation
import Testing
@testable import VeraFlow

/// The user's edits to action items ride in `ActionItemsState`, never in the payload (v1.1 plan item 2).
@MainActor
struct ActionItemEditsTests {
    private var payload: SummaryPayload {
        .general(GeneralSummary(
            title: "t", overview: "o", keyPoints: [], decisions: [],
            actionItems: [
                ActionItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, task: "Call the county", owner: "Speaker 2", ownerSpeakerKey: "S2", dueText: "Monday", timestamp: 4),
                ActionItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, task: "Order tile", owner: "", timestamp: 9),
            ],
            openQuestions: []
        ))
    }

    private let first = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let second = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    @Test("Overrides replace the editable fields and keep the id and timestamp; removed items vanish; added items come last")
    func resolution() {
        var state = ActionItemsState()
        #expect(payload.resolvedActionItems(applying: state).map(\.task) == ["Call the county", "Order tile"])

        var edited = payload.actionItems[0]
        edited.task = "Call the county about the permit"
        edited.owner = "Dana"
        edited.ownerSpeakerKey = nil
        edited.dueDate = Date(timeIntervalSince1970: 1_800_000_000)
        state.save(edited, isAdded: false)
        state.remove(second)
        let manual = ActionItem(task: "Book the inspector")
        state.save(manual, isAdded: true)

        let resolved = payload.resolvedActionItems(applying: state)
        #expect(resolved.map(\.task) == ["Call the county about the permit", "Book the inspector"])
        #expect(resolved[0].id == first)
        #expect(resolved[0].timestamp == 4, "the audio link is not editable")
        #expect(resolved[0].owner == "Dana")
        #expect(resolved[0].ownerSpeakerKey == nil)
        #expect(resolved[0].dueDate == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(resolved[1].timestamp == nil)
        #expect(state.hasEdits)
        #expect(state.isAdded(manual.id))
        #expect(!state.isAdded(first))

        // Editing an added item replaces it in place; removing it drops it.
        var renamed = manual
        renamed.task = "Book the inspector for Friday"
        state.save(renamed, isAdded: false)
        #expect(payload.resolvedActionItems(applying: state).last?.task == "Book the inspector for Friday")
        state.remove(manual.id)
        #expect(payload.resolvedActionItems(applying: state).count == 1)
        #expect(state.removedItemIDs == [second])
    }

    @Test("Completion is cleared for a removed item; unknown ids are ignored")
    func completion() {
        var state = ActionItemsState()
        state.completedItemIDs.insert(second)
        state.remove(second)
        #expect(state.completedItemIDs.isEmpty)
        state.overrides[UUID()] = ActionItemOverride(task: "ghost")
        #expect(payload.resolvedActionItems(applying: state).count == 1)
    }

    @Test("A pre-1.1 state without the edit keys decodes, and a state with edits round-trips")
    func coding() throws {
        let legacy = Data(#"{"completedItemIDs":["00000000-0000-0000-0000-000000000001"],"reminderIDs":[]}"#.utf8)
        let decoded = try JSONDecoder().decode(ActionItemsState.self, from: legacy)
        #expect(decoded.completedItemIDs == [first])
        #expect(!decoded.hasEdits)

        var state = ActionItemsState()
        state.save(ActionItem(task: "Added"), isAdded: true)
        state.remove(second)
        state.overrides[first] = ActionItemOverride(task: "Changed", dueDate: Date(timeIntervalSince1970: 1_800_000_000))
        let roundTrip = try JSONDecoder().decode(ActionItemsState.self, from: try JSONEncoder().encode(state))
        #expect(roundTrip == state)
    }

    @Test("Exports, the Reminders list and the library card read the edited list")
    func consumers() throws {
        let recording = PreviewData.sampleRecording()
        let record = try #require(recording.currentSummary)
        var state = try record.actionItems()
        state.save(ActionItem(task: "Order the permit forms"), isAdded: true)
        try record.store(state)

        #expect(try record.resolvedPayload().actionItems.map(\.task) == ["Call the county about the permit", "Order the permit forms"])
        #expect(LibraryCardModel(recording: recording).actionCount == 2)
        let document = ExportDocument.make(from: recording, includeTranscript: false)
        #expect(ExportRenderer.actionItemsText(for: document).contains("Order the permit forms"))
        #expect(try record.payload().actionItems.count == 1, "the model's output is untouched")
    }
}
