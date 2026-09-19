import Foundation
import Testing
@testable import VeraFlow

/// The model padding a thin transcript by repeating itself (Jeremy's 1:58 "Coaching Staff"
/// recording, 2026-09-19). `.maximumCount` bounded the repetition; these rules remove it.
struct SummaryDeduplicatorTests {
    /// Verbatim from the summary on screen: three subjects, one set of points, and those points
    /// are the open questions.
    private let repeatedPoints = [
        "How will the shortened camp affect the team's performance?",
        "What are the coach's plans for Adam Fantili?",
        "How will the team handle the young players' development?",
    ]

    @Test("Topics with identical point lists collapse to the first")
    func identicalTopics() {
        let topics = [
            KeyPointTopic(title: "Team Performance and Reflection", points: repeatedPoints),
            KeyPointTopic(title: "Press and Media Relations", points: repeatedPoints),
            KeyPointTopic(title: "Team Dynamics and Player Development", points: repeatedPoints),
        ]
        let cleaned = SummaryDeduplicator.topics(topics)
        #expect(cleaned.count == 1)
        #expect(cleaned[0].title == "Team Performance and Reflection")
        #expect(cleaned[0].points == repeatedPoints)
    }

    @Test("A topic keeps the points no earlier topic used")
    func partialOverlap() {
        let topics = [
            KeyPointTopic(title: "Camp", points: ["Camp was shortened to four days.", "Ice time was cut."]),
            KeyPointTopic(title: "Roster", points: ["Ice time was cut.", "Two rookies made the roster."]),
        ]
        let cleaned = SummaryDeduplicator.topics(topics)
        #expect(cleaned.count == 2)
        #expect(cleaned[1].points == ["Two rookies made the roster."], "the shared point stays under the first subject only")
    }

    @Test("Points that are open questions repeated back are not key points")
    func questionsAreNotPoints() {
        let topics = [KeyPointTopic(title: "Team Performance and Reflection", points: repeatedPoints)]
        let cleaned = SummaryDeduplicator.topics(topics, questions: repeatedPoints)
        #expect(cleaned.isEmpty, "every point was an open question, so the topic has nothing left to show")
    }

    @Test("A statement is kept even when an open question says something similar")
    func statementsSurvive() {
        let topics = [KeyPointTopic(title: "Camp", points: ["The shortened camp will affect the team's performance."])]
        let cleaned = SummaryDeduplicator.topics(topics, questions: ["How will the shortened camp affect the team's performance?"])
        #expect(cleaned.count == 1, "only a point phrased as a question is treated as a stray question")
    }

    @Test("Identity ignores case, accents, punctuation and spacing")
    func normalization() {
        #expect(SummaryDeduplicator.key("Ice time was cut.") == SummaryDeduplicator.key("ice  time was cut"))
        #expect(SummaryDeduplicator.key("Coach's plan") == SummaryDeduplicator.key("coachs   plan"))
        #expect(SummaryDeduplicator.key("Café") == SummaryDeduplicator.key("cafe"))
        #expect(SummaryDeduplicator.key("Ice time was cut.") != SummaryDeduplicator.key("Ice time was added."))
    }

    @Test("A repeated heading goes even when its points differ")
    func repeatedTitle() {
        let topics = [
            KeyPointTopic(title: "Roster", points: ["Two rookies made the roster."]),
            KeyPointTopic(title: "roster", points: ["Something else entirely."]),
        ]
        #expect(SummaryDeduplicator.topics(topics).count == 1)
    }

    @Test("Blank and repeated lines are dropped from a plain list, order kept")
    func uniqueList() {
        let cleaned = SummaryDeduplicator.unique(["Ship it.", "", "ship it", "Hold the release.", "   "])
        #expect(cleaned == ["Ship it.", "Hold the release."])
    }

    @Test("A general summary cleans its topics, questions and flat key points together")
    func generalPayload() {
        let summary = GeneralSummary(
            title: "Coaching Staff and Team Preparation",
            overview: "Three coaches talk before camp.",
            keyPoints: repeatedPoints + repeatedPoints,
            topics: [
                KeyPointTopic(title: "Team Performance and Reflection", points: repeatedPoints),
                KeyPointTopic(title: "Press and Media Relations", points: repeatedPoints),
                KeyPointTopic(title: "Camp", points: ["Camp was shortened to four days."]),
            ],
            decisions: ["Shorten camp.", "shorten camp"],
            actionItems: [],
            openQuestions: repeatedPoints + [repeatedPoints[0]]
        )
        guard case .general(let cleaned) = SummaryDeduplicator.cleaned(.general(summary)) else {
            Issue.record("wrong case")
            return
        }
        #expect(cleaned.openQuestions == repeatedPoints)
        #expect(cleaned.topics.count == 1, "only the subject with a real point of its own survives")
        #expect(cleaned.topics[0].title == "Camp")
        #expect(cleaned.keyPoints == ["Camp was shortened to four days."], "the flat list matches what the topics now say")
        #expect(cleaned.decisions == ["Shorten camp."])
    }

    @Test("When every topic is dropped the flat key points go with them")
    func everyTopicDropped() {
        let summary = GeneralSummary(
            title: "T", overview: "O",
            keyPoints: repeatedPoints,
            topics: [KeyPointTopic(title: "Team Performance and Reflection", points: repeatedPoints)],
            decisions: [], actionItems: [], openQuestions: repeatedPoints
        )
        guard case .general(let cleaned) = SummaryDeduplicator.cleaned(.general(summary)) else {
            Issue.record("wrong case")
            return
        }
        #expect(cleaned.topics.isEmpty)
        #expect(cleaned.keyPoints.isEmpty, "keyPoints is the flat copy of those topics; it must not put them back")
        #expect(cleaned.openQuestions == repeatedPoints, "the questions themselves are still questions")
    }

    @Test("An older summary with no topics keeps its flat key points, deduplicated")
    func flatOnlySummary() {
        let summary = GeneralSummary(
            title: "T", overview: "O",
            keyPoints: ["Ice time was cut.", "ice time was cut", "Two rookies made the roster."],
            decisions: [], actionItems: [], openQuestions: []
        )
        guard case .general(let cleaned) = SummaryDeduplicator.cleaned(.general(summary)) else {
            Issue.record("wrong case")
            return
        }
        #expect(cleaned.keyPoints == ["Ice time was cut.", "Two rookies made the roster."])
    }

    @Test("Walk-through areas deduplicate tasks, measurements and materials across areas")
    func walkthroughAreas() {
        let areas = [
            WorkArea(
                name: "Kitchen",
                tasks: ["Replace the counter."],
                measurements: [Measurement(item: "North wall", value: "12 ft 4 in", timestamp: nil)],
                materials: [Material(name: "Quartz slab", quantity: "1", notes: "")]
            ),
            WorkArea(
                name: "Bath",
                tasks: ["Replace the counter."],
                measurements: [Measurement(item: "North wall", value: "12 ft 4 in", timestamp: nil)],
                materials: [Material(name: "Quartz slab", quantity: "1", notes: "")]
            ),
            WorkArea(
                name: "Hall",
                tasks: ["Patch the ceiling."],
                measurements: [],
                materials: []
            ),
        ]
        let cleaned = SummaryDeduplicator.areas(areas)
        #expect(cleaned.map(\.name) == ["Kitchen", "Bath", "Hall"], "an area is also a chapter, so it stays even when its contents were all repeats")
        #expect(cleaned[0].tasks == ["Replace the counter."])
        #expect(cleaned[1].tasks.isEmpty)
        #expect(cleaned[1].measurements.isEmpty)
        #expect(cleaned[1].materials.isEmpty)
        #expect(cleaned[2].tasks == ["Patch the ceiling."])
    }

    @Test("A measurement with the same item but a different value is kept")
    func distinctMeasurements() {
        let areas = [
            WorkArea(name: "Kitchen", tasks: [], measurements: [
                Measurement(item: "North wall", value: "12 ft 4 in", timestamp: nil),
                Measurement(item: "North wall", value: "8 ft 2 in", timestamp: nil),
            ], materials: []),
        ]
        #expect(SummaryDeduplicator.areas(areas)[0].measurements.count == 2)
    }
}
