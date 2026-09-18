import Foundation
import Testing
@testable import VeraFlow

struct LibraryCardModelTests {
    private let english = Locale(identifier: "en_US")

    @Test("Snippets prefer the summary overview, then the first transcript line, and stay one line")
    func snippets() {
        #expect(LibraryCardModel.snippet(overview: " Agreed on the permit plan. ", firstTranscriptLine: "Hi", stage: .ready) == "Agreed on the permit plan.")
        #expect(LibraryCardModel.snippet(overview: "", firstTranscriptLine: "We need\nthe permit", stage: .ready) == "We need the permit")
        #expect(LibraryCardModel.snippet(overview: nil, firstTranscriptLine: nil, stage: .recorded) == "Waiting to transcribe.")
        #expect(LibraryCardModel.snippet(overview: nil, firstTranscriptLine: nil, stage: .ready) == "")
        let long = String(repeating: "word ", count: 60)
        let cut = LibraryCardModel.snippet(overview: long, firstTranscriptLine: nil, stage: .ready)
        #expect(cut.hasSuffix("…"))
        #expect(cut.count <= 141)
    }

    @Test("Durations use minutes:seconds under an hour and add hours above it")
    func durations() {
        #expect(LibraryCardModel.durationText(272) == "4:32")
        #expect(LibraryCardModel.durationText(3_723) == "1:02:03")
    }

    @Test("Recordings group by day with Today and Yesterday first; non-date sorts don't group")
    func grouping() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_789_040_000) // 2026-09-10 11:33 UTC (a Thursday)
        let today = Recording(title: "a", createdAt: now.addingTimeInterval(-3_600), stage: .ready)
        let yesterday = Recording(title: "b", createdAt: now.addingTimeInterval(-86_400), stage: .ready)
        let older = Recording(title: "c", createdAt: now.addingTimeInterval(-5 * 86_400), stage: .ready)
        let older2 = Recording(title: "d", createdAt: now.addingTimeInterval(-5 * 86_400 - 60), stage: .ready)

        let sections = LibraryGrouping.sections([today, yesterday, older, older2], sort: .newest, now: now, calendar: calendar, locale: english)
        #expect(sections.map(\.title) == ["Today", "Yesterday", "Saturday, Sep 5"])
        #expect(sections.last?.recordings.map(\.title) == ["c", "d"])

        let flat = LibraryGrouping.sections([today, older], sort: .title, now: now, calendar: calendar, locale: english)
        #expect(flat.count == 1)
        #expect(flat.first?.title == "")
        #expect(LibraryGrouping.sections([], sort: .title, now: now, calendar: calendar, locale: english).isEmpty)
    }

    @Test("A card keeps a user-given title, takes the summary's title only over the automatic one, and shows gist and action count")
    @MainActor
    func cardFromSummary() throws {
        let recording = PreviewData.sampleRecording(createdAt: Date(timeIntervalSince1970: 1_789_000_000))
        let payload = try #require(try recording.currentSummary?.payload())
        #expect(LibraryCardModel(recording: recording, locale: english).title == "Kitchen remodel walk-through")

        recording.title = Recording.suggestedTitle(for: recording.createdAt)
        #expect(recording.hasDefaultTitle)
        let card = LibraryCardModel(recording: recording, locale: english)
        #expect(card.title == payload.title)
        #expect(card.snippet.hasPrefix(String(payload.overview.prefix(20))))
        #expect(card.actionCount == payload.actionItems.count)
        #expect(card.speakerCount == recording.speakers.count)
        #expect(card.status == nil)
    }
}
