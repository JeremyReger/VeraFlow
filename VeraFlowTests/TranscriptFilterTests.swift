import Foundation
import Testing
@testable import VeraFlow

struct TranscriptFilterTests {
    private let segments: [TranscriptFilterSegment] = [
        TranscriptFilterSegment(index: 0, speakerKey: "S1", start: 0, end: 10, text: "We need the permit first."),
        TranscriptFilterSegment(index: 1, speakerKey: "S2", start: 10, end: 25, text: "I can call the county on Monday."),
        TranscriptFilterSegment(index: 2, speakerKey: "S1", start: 25, end: 30, text: "Then the footer goes in."),
        TranscriptFilterSegment(index: 3, speakerKey: nil, start: 30, end: 31, text: "Permit or not."),
    ]

    @Test("No speaker picked shows every paragraph and no count")
    func showsAll() {
        let filter = TranscriptFilter()
        #expect(filter.visible(segments).map(\.index) == [0, 1, 2, 3])
        #expect(filter.countText(segments) == "")
        #expect(!filter.isNarrowing)
    }

    @Test("A speaker chip narrows to that speaker's paragraphs and reads the count and talk time")
    func bySpeaker() {
        var filter = TranscriptFilter()
        filter.speakerKey = "S1"
        #expect(filter.visible(segments).map(\.index) == [0, 2])
        #expect(filter.talkTime(segments) == 15)
        #expect(filter.countText(segments) == "2 paragraphs · 0:15 of talk time")
        #expect(filter.isNarrowing)

        filter.speakerKey = "S2"
        #expect(filter.countText(segments) == "1 paragraph · 0:15 of talk time")

        filter.speakerKey = "S9"
        #expect(filter.visible(segments).isEmpty)
        #expect(filter.countText(segments) == "0 paragraphs · 0:00 of talk time")
    }

    @Test("Search matches only within the picked speaker's paragraphs and keeps transcript indices")
    func searchWithinSpeaker() {
        var filter = TranscriptFilter()
        filter.query = "permit"
        #expect(filter.matches(segments) == [0, 3])
        #expect(filter.countText(segments) == "2 matches")

        filter.speakerKey = "S1"
        #expect(filter.matches(segments) == [0])
        #expect(filter.countText(segments) == "1 match")

        filter.query = "   "
        #expect(!filter.isSearching)
        #expect(filter.matches(segments).isEmpty)
    }

    @Test("Talk time for one speaker equals the Audio tab's share for that speaker")
    func agreesWithTalkTime() {
        var filter = TranscriptFilter()
        filter.speakerKey = "S2"
        let shares = TalkTime.shares(segments: segments.map { (speakerKey: $0.speakerKey, start: $0.start, end: $0.end) })
        let share = shares.first { $0.speakerKey == "S2" }
        #expect(share?.seconds == filter.talkTime(segments))
    }
}
