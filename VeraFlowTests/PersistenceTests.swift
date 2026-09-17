import Foundation
import SwiftData
import Testing
@testable import VeraFlow

@MainActor
struct PersistenceTests {
    @Test("Recording round-trips with children and cascades on delete")
    func recordingRoundTrip() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext

        let recording = PreviewData.sampleRecording()
        context.insert(recording)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Recording>())
        #expect(fetched.count == 1)
        let loaded = try #require(fetched.first)
        #expect(loaded.title == "Kitchen remodel walk-through")
        #expect(loaded.stage == .ready)
        #expect(loaded.templateID == .walkthrough)
        #expect(loaded.speakers.count == 2)
        #expect(loaded.segments.count == 2)
        #expect(loaded.bookmarks.count == 1)
        #expect(loaded.summaries.count == 1)
        #expect(loaded.orderedSegments.map(\.index) == [0, 1])
        #expect(loaded.orderedSegments.first?.words.isEmpty == false)

        context.delete(loaded)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<Recording>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<TranscriptSegment>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Speaker>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Bookmark>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<SummaryRecord>()) == 0)
    }

    @Test("Summary payload decodes from the stored record")
    func summaryPayloadRoundTrip() throws {
        let recording = PreviewData.sampleRecording()
        let record = try #require(recording.currentSummary)
        let payload = try record.payload()
        #expect(payload.templateID == .walkthrough)
        #expect(payload.actionItems.count == 1)
        #expect(payload.actionItems.first?.ownerSpeakerKey == "S2")

        let state = try record.actionItems()
        #expect(state.completedItemIDs.isEmpty)
    }

    @Test("Segment edits are tracked against the original text")
    func segmentEditTracking() {
        let segment = TranscriptSegment(index: 0, start: 0, end: 1, text: "hello")
        #expect(!segment.isEdited)
        segment.text = "hello there"
        #expect(segment.isEdited)
        #expect(segment.originalText == "hello")
    }

    @Test("Suggested title includes the date")
    func suggestedTitle() {
        let date = Date(timeIntervalSince1970: 1_789_000_000)
        let title = Recording.suggestedTitle(for: date, locale: Locale(identifier: "en_US"))
        #expect(title.hasPrefix("Meeting · "))
        #expect(title.count > "Meeting · ".count)
    }
}
