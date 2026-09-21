import Foundation
import Testing
@testable import VeraFlow

/// Placing summary lines in the transcript (Jeremy, 2026-09-21): tapping a line plays the moment
/// it came from, so the match has to be right or absent — never merely plausible.
struct SummaryMomentIndexTests {
    private let segments: [(start: TimeInterval, text: String)] = [
        (0, "Welcome everyone. Let us start with the budget review for next quarter."),
        (60, "We decided to postpone the launch until the third quarter."),
        (120, "Marcus raised a concern over the vendor contract."),
        (180, "Priya said the permit is still sitting with the county."),
        (240, "She expects an answer on Friday, or Monday at the latest."),
    ]

    private func summary(
        keyPoints: [String] = [],
        decisions: [String] = [],
        openQuestions: [String] = [],
        actionItems: [ActionItem] = []
    ) -> SummaryPayload {
        .general(GeneralSummary(
            title: "Weekly sync",
            overview: "The team went over the budget, the launch date and the permit.",
            keyPoints: keyPoints,
            decisions: decisions,
            actionItems: actionItems,
            openQuestions: openQuestions
        ))
    }

    @Test("A line is placed on the paragraph that says it")
    func placesOnItsParagraph() {
        let payload = summary(decisions: ["The team decided to postpone the launch until the third quarter"])
        let index = SummaryMomentIndex(displayed: payload, segments: segments)
        #expect(index.start(for: "The team decided to postpone the launch until the third quarter") == 60)
    }

    @Test("A line distilled from two paragraphs in a row plays from the first of them")
    func placesOnARunOfParagraphs() {
        let line = "Priya expects an answer on the permit by Friday"
        let index = SummaryMomentIndex(displayed: summary(keyPoints: [line]), segments: segments)
        // Neither paragraph alone shares enough words with the line; together they do, and
        // playback starts where the run starts rather than halfway through it.
        #expect(index.start(for: line) == 180)
    }

    @Test("A line the transcript doesn't support isn't placed at all")
    func leavesUnsupportedLinesAlone() {
        let index = SummaryMomentIndex(displayed: summary(
            keyPoints: ["Everyone agreed the pizza was excellent", "Budget approved"]
        ), segments: segments)
        #expect(index.start(for: "Everyone agreed the pizza was excellent") == nil)
        #expect(index.start(for: "Budget approved") == nil, "two meaningful words is a coincidence, not a match")
        #expect(index.isEmpty)
    }

    @Test("Whitespace around a line doesn't lose its place")
    func trimsTheKey() {
        let index = SummaryMomentIndex(displayed: summary(
            decisions: ["  The team decided to postpone the launch until the third quarter  "]
        ), segments: segments)
        #expect(index.start(for: "The team decided to postpone the launch until the third quarter") == 60)
    }

    @Test("A translated line is placed by the model's own line in the same position")
    func fallsBackToTheModelsLine() {
        let model = summary(decisions: ["The team decided to postpone the launch until the third quarter"])
        let translated = summary(decisions: ["Das Team hat den Start auf das dritte Quartal verschoben"])
        let index = SummaryMomentIndex(displayed: translated, model: model, segments: segments)
        #expect(index.start(for: "Das Team hat den Start auf das dritte Quartal verschoben") == 60)
    }

    @Test("Action items are left out: they carry their own timestamp and their own play button")
    func skipsActionItems() {
        let payload = summary(actionItems: [
            ActionItem(task: "Chase the county about the permit Priya is waiting on", timestamp: 180),
        ])
        let index = SummaryMomentIndex(displayed: payload, segments: segments)
        #expect(index.start(for: "Chase the county about the permit Priya is waiting on") == nil)
    }

    @Test("Every prose line the Summary tab draws is in the index")
    func indexesEveryDrawnList() {
        let payload = summary(
            keyPoints: ["The budget review opened the quarter"],
            decisions: ["The team decided to postpone the launch until the third quarter"],
            openQuestions: ["Marcus raised a concern over the vendor contract"]
        )
        #expect(SummaryMomentIndex.lines(of: payload).count == 3)
        let index = SummaryMomentIndex(displayed: payload, segments: segments)
        #expect(index.start(for: "The team decided to postpone the launch until the third quarter") == 60)
        #expect(index.start(for: "Marcus raised a concern over the vendor contract") == 120)
    }

    @Test("A walk-through indexes its area tasks and its lists")
    func indexesWalkthroughLines() {
        let payload = SummaryPayload.walkthrough(WalkthroughSummary(
            title: "Footing walk-through",
            location: "",
            overview: "",
            areas: [WorkArea(
                name: "North wall",
                tasks: ["Chase the county over the permit Priya mentioned"],
                measurements: [],
                materials: []
            )],
            customerRequests: [],
            issuesFound: ["Marcus raised a concern over the vendor contract"],
            quoteNotes: [],
            actionItems: []
        ))
        #expect(SummaryMomentIndex.lines(of: payload).count == 2)
        let index = SummaryMomentIndex(displayed: payload, segments: segments)
        #expect(index.start(for: "Marcus raised a concern over the vendor contract") == 120)
    }
}
