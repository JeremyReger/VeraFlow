import Foundation
import SwiftData
import Testing
@testable import VeraFlow

@MainActor
struct SpeakerActionsTests {
    private func makeRecording() throws -> (ModelContainer, Recording) {
        let container = try ModelContainerFactory.makeInMemory()
        let recording = Recording(title: "Two people", stage: .diarized)
        recording.speakers = [Speaker.default(number: 1), Speaker.default(number: 2)]
        recording.segments = [
            TranscriptSegment(index: 0, start: 0, end: 1, text: "Hello", speakerKey: "S1"),
            TranscriptSegment(index: 1, start: 1, end: 2, text: "Hi there", speakerKey: "S2"),
            TranscriptSegment(index: 2, start: 2, end: 3, text: "Welcome", speakerKey: "S1"),
        ]
        container.mainContext.insert(recording)
        try container.mainContext.save()
        return (container, recording)
    }

    @Test("Rename trims the name and rejects an empty one")
    func rename() throws {
        let (container, recording) = try makeRecording()
        let actions = SpeakerActions(context: container.mainContext)
        let speaker = try #require(recording.speakers.first { $0.key == "S1" })
        try actions.rename(speaker, to: "  Jeremy ")
        #expect(speaker.displayName == "Jeremy")
        #expect(throws: SpeakerActions.ActionError.emptyName) {
            try actions.rename(speaker, to: "   ")
        }
        #expect(speaker.displayName == "Jeremy")
    }

    @Test("Merge moves every paragraph to the target and removes the source")
    func merge() throws {
        let (container, recording) = try makeRecording()
        let actions = SpeakerActions(context: container.mainContext)
        let source = try #require(recording.speakers.first { $0.key == "S2" })
        let target = try #require(recording.speakers.first { $0.key == "S1" })
        try actions.merge(source, into: target, in: recording)
        #expect(recording.speakers.map(\.key) == ["S1"])
        #expect(recording.orderedSegments.allSatisfy { $0.speakerKey == "S1" })
        let stored = try container.mainContext.fetch(FetchDescriptor<Speaker>())
        #expect(stored.count == 1)
    }

    @Test("Change speaker for one paragraph, including to a brand-new speaker")
    func assign() throws {
        let (container, recording) = try makeRecording()
        let actions = SpeakerActions(context: container.mainContext)
        let second = try #require(recording.speakers.first { $0.key == "S2" })
        let last = recording.orderedSegments[2]
        try actions.assign(last, to: second)
        #expect(last.speakerKey == "S2")

        let created = try actions.assignToNewSpeaker(recording.orderedSegments[0], in: recording)
        #expect(created.key == "S3")
        #expect(created.displayName == "Speaker 3")
        #expect(recording.orderedSegments[0].speakerKey == "S3")
        #expect(recording.speakers.count == 3)
    }

    @Test("The next speaker key skips keys still in use after a merge")
    func nextKeySkipsUsed() {
        let recording = Recording(title: "x")
        recording.speakers = [Speaker.default(number: 1), Speaker.default(number: 3)]
        let next = SpeakerActions.nextSpeaker(for: recording)
        #expect(next.key == "S4", "S3 is taken, so counting from the speaker count lands on S3 and moves on")
        #expect(next.colorIndex == 3)
    }

    @Test("The controller reports an empty name instead of throwing")
    func controllerRename() throws {
        let (container, recording) = try makeRecording()
        let controller = SpeakerActionsController(actions: SpeakerActions(context: container.mainContext))
        let speaker = try #require(recording.speakers.first { $0.key == "S1" })
        controller.beginRename(speaker)
        #expect(controller.renameDraft == "Speaker 1")
        controller.renameDraft = ""
        controller.commitRename(speaker)
        #expect(controller.renameTarget == nil)
        #expect(controller.errorMessage == "A speaker needs a name.")
        #expect(speaker.displayName == "Speaker 1")
    }
}
