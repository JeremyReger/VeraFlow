import Foundation
import Testing
@testable import VeraFlow

/// Chapter start validation (v1.1 plan item 12): the model suggests, Swift decides.
struct ChapterPostProcessorTests {
    private let segments: [(start: TimeInterval, text: String)] = [
        (0, "Welcome everyone, let's start with the budget review for next quarter."),
        (120, "Now the hiring plan: two engineers and a designer."),
        (300, "Last thing, the office move timeline and the lease."),
    ]

    @Test("Valid starts are kept in order; the first chapter always starts at zero")
    func validStarts() {
        let starts = ChapterPostProcessor.starts(for: ["Budget", "Hiring", "Office move"], given: [5, 125, 310], duration: 400, segments: segments)
        #expect(starts == [0, 125, 310])
    }

    @Test("Out-of-range starts are clamped, and a chapter too close to the previous one is dropped")
    func clampAndGap() {
        let starts = ChapterPostProcessor.starts(for: ["A", "B", "C", "D"], given: [-3, 130, 140, 900], duration: 400, segments: [])
        #expect(starts == [0, 130, nil, 400])
        let unordered = ChapterPostProcessor.starts(for: ["A", "B", "C"], given: [10, 300, 100], duration: 400, segments: [])
        #expect(unordered == [0, 300, nil], "a start earlier than the previous chapter is dropped, not reordered")
    }

    @Test("A missing start is placed on the paragraph that shares its words; otherwise the chapter is dropped")
    func fallback() {
        let starts = ChapterPostProcessor.starts(for: ["Budget review", "Hiring plan", "Parking"], given: [nil, nil, nil], duration: 400, segments: segments)
        #expect(starts == [0, 120, nil])
        #expect(ChapterPostProcessor.nearestSegmentStart(for: "Office move timeline", in: segments) == 300)
        #expect(ChapterPostProcessor.nearestSegmentStart(for: "Budget", in: segments) == nil, "one word is not enough")
    }

    @Test("Fewer than two placed chapters means no chapters; blank titles are skipped")
    func chapterList() {
        #expect(ChapterPostProcessor.chapters(titles: ["Only"], starts: [0]).isEmpty)
        #expect(ChapterPostProcessor.chapters(titles: ["A", "B"], starts: [0, nil]).isEmpty)
        let chapters = ChapterPostProcessor.chapters(titles: ["A", " ", "C"], starts: [0, 50, 100])
        #expect(chapters.map(\.title) == ["A", "C"])
        #expect(chapters.map(\.start) == [0, 100])
    }

    @Test("Payloads carry chapters through post-processing and decode without them")
    func payloads() throws {
        var payload = SummaryPayload.general(GeneralSummary(
            title: "t", overview: "o", keyPoints: [],
            topics: [KeyPointTopic(title: "Budget review", points: ["x"], start: 4), KeyPointTopic(title: "Hiring plan", points: ["y"], start: nil)],
            decisions: [], actionItems: [], openQuestions: []
        ))
        let processed = payload.postProcessed(
            with: ActionItemPostProcessor(dueDates: FakeDueDateResolver()),
            context: .init(recordedAt: .now, duration: 400, segments: segments)
        )
        #expect(processed.chapters.map(\.start) == [0, 120])
        #expect(processed.chapters.map(\.title) == ["Budget review", "Hiring plan"])
        payload.setChapterStarts([nil, nil])
        #expect(payload.chapters.isEmpty)

        // A v2 payload without topics or starts still decodes.
        let legacy = Data("""
        {"client":{"_0":{"title":"t","overview":"o","clientGoals":[],"concerns":[],"decisions":[],"actionItems":[],"nextMeeting":"","openQuestions":[]}}}
        """.utf8)
        let decoded = try JSONDecoder().decode(SummaryPayload.self, from: legacy)
        guard case .client(let client) = decoded else {
            Issue.record("wrong template")
            return
        }
        #expect(client.topics.isEmpty)
        #expect(decoded.chapters.isEmpty)

        let walkthrough = SummaryPayload.walkthrough(WalkthroughSummary(
            title: "t", location: "", overview: "o",
            areas: [WorkArea(name: "Kitchen", tasks: [], measurements: [], materials: [], start: 0), WorkArea(name: "Bath", tasks: [], measurements: [], materials: [], start: 90)],
            customerRequests: [], issuesFound: [], quoteNotes: [], actionItems: []
        ))
        #expect(walkthrough.chapters.map(\.title) == ["Kitchen", "Bath"])
        let roundTrip = try JSONDecoder().decode(SummaryPayload.self, from: try walkthrough.encoded())
        #expect(roundTrip == walkthrough)
    }
}
