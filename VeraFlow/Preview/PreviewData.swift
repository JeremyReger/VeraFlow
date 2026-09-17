import Foundation
import SwiftData

/// Sample data for SwiftUI previews and tests.
@MainActor
enum PreviewData {
    /// An in-memory container, optionally seeded with sample recordings.
    static func container(populated: Bool = true) -> ModelContainer {
        do {
            let container = try ModelContainerFactory.makeInMemory()
            if populated {
                let context = container.mainContext
                for recording in sampleRecordings() {
                    context.insert(recording)
                }
                try context.save()
            }
            return container
        } catch {
            fatalError("Preview container failed: \(error)")
        }
    }

    /// A finished two-speaker recording with a transcript and a summary.
    static func sampleRecording(createdAt: Date = Date(timeIntervalSince1970: 1_789_000_000)) -> Recording {
        let recording = Recording(
            title: "Kitchen remodel walk-through",
            createdAt: createdAt,
            duration: 7,
            stage: .ready,
            templateID: .walkthrough,
            tags: ["contractor"],
            isFavorite: true
        )
        recording.speakers = [Speaker.default(number: 1), Speaker.default(number: 2)]

        let words = FakeTranscriptionService.sampleWords
        let aligned = FakeTranscriptAligner().align(words: words, turns: FakeDiarizationService.sampleTurns)
        recording.segments = aligned.enumerated().map { index, segment in
            TranscriptSegment(
                index: index,
                start: segment.start,
                end: segment.end,
                text: segment.text,
                speakerKey: segment.speakerKey,
                words: segment.words
            )
        }

        recording.bookmarks = [Bookmark(time: 3.6, note: "Permit question")]

        let payload = SummaryPayload.walkthrough(WalkthroughSummary(
            title: "Kitchen remodel walk-through",
            location: "",
            overview: "Walked the kitchen with the customer. The permit must be in hand before the footer is poured.",
            areas: [
                WorkArea(
                    name: "Kitchen",
                    tasks: ["Pour footer after permit"],
                    measurements: [],
                    materials: []
                ),
            ],
            customerRequests: [],
            issuesFound: [],
            quoteNotes: ["Permit required before footer"],
            actionItems: [
                ActionItem(task: "Call the county about the permit", owner: "Speaker 2", ownerSpeakerKey: "S2", dueText: "on Monday", timestamp: 3.6),
            ]
        ))
        if let data = try? payload.encoded() {
            recording.summaries = [
                SummaryRecord(createdAt: createdAt.addingTimeInterval(120), templateID: .walkthrough, payloadJSON: data, modelInfo: "PreviewData"),
            ]
        }
        return recording
    }

    /// A few recordings at different pipeline stages.
    static func sampleRecordings() -> [Recording] {
        let base = Date(timeIntervalSince1970: 1_789_000_000)
        return [
            sampleRecording(createdAt: base),
            Recording(title: "Weekly client check-in", createdAt: base.addingTimeInterval(-86_400), duration: 1_830, stage: .transcribing, templateID: .client),
            Recording(title: "Lecture · Materials science", createdAt: base.addingTimeInterval(-172_800), duration: 3_600, source: .imported, stage: .failed, failureMessage: "Speech assets not installed"),
        ]
    }
}
