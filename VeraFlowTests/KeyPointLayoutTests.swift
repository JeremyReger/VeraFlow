import Foundation
import Testing
@testable import VeraFlow

struct KeyPointLayoutTests {
    @Test("Two or more titled topics are grouped; untitled points lead as a plain block")
    func grouped() {
        let groups = KeyPointLayout.groups(topics: [
            KeyPointTopic(title: "Budget", points: ["Cap is 40k", " Contingency 10% "]),
            KeyPointTopic(title: "", points: ["Meeting ran long"]),
            KeyPointTopic(title: "Schedule", points: ["Start in March"]),
            KeyPointTopic(title: "Empty", points: ["  "]),
        ], keyPoints: [])
        #expect(groups == [
            KeyPointGroup(title: nil, points: ["Meeting ran long"]),
            KeyPointGroup(title: "Budget", points: ["Cap is 40k", "Contingency 10%"]),
            KeyPointGroup(title: "Schedule", points: ["Start in March"]),
        ])
    }

    @Test("One subject reads as a plain list; no topics falls back to the flat key points")
    func flat() {
        let one = KeyPointLayout.groups(topics: [KeyPointTopic(title: "Budget", points: ["Cap is 40k", "No overtime"])], keyPoints: [])
        #expect(one == [KeyPointGroup(title: nil, points: ["Cap is 40k", "No overtime"])])
        let legacy = KeyPointLayout.groups(topics: [], keyPoints: ["Old point"])
        #expect(legacy == [KeyPointGroup(title: nil, points: ["Old point"])])
        #expect(KeyPointLayout.groups(topics: [], keyPoints: []).isEmpty)
    }

    @Test("Summaries saved before topics existed still decode")
    func decodesWithoutTopics() throws {
        let json = """
        {"title":"T","overview":"O","keyPoints":["a","b"],"decisions":[],"actionItems":[],"openQuestions":[]}
        """
        let summary = try JSONDecoder().decode(GeneralSummary.self, from: Data(json.utf8))
        #expect(summary.topics.isEmpty)
        #expect(summary.keyPointGroups == [KeyPointGroup(title: nil, points: ["a", "b"])])

        let grouped = GeneralSummary(
            title: "T", overview: "O", keyPoints: ["a", "b"],
            topics: [KeyPointTopic(title: "X", points: ["a"]), KeyPointTopic(title: "Y", points: ["b"])],
            decisions: [], actionItems: [], openQuestions: []
        )
        let roundTrip = try JSONDecoder().decode(GeneralSummary.self, from: JSONEncoder().encode(grouped))
        #expect(roundTrip == grouped)
    }

    @Test("Exports write subject headings as lines with bullets under them")
    @MainActor
    func exports() {
        let summary = GeneralSummary(
            title: "Planning", overview: "Overview.", keyPoints: ["a", "b"],
            topics: [KeyPointTopic(title: "Budget", points: ["a"]), KeyPointTopic(title: "Schedule", points: ["b"])],
            decisions: [], actionItems: [], openQuestions: []
        )
        var document = ExportDocument.make(from: PreviewData.sampleRecording(), includeTranscript: false)
        document.summary = .general(summary)
        let sections = ExportRenderer.summarySections(document)
        let keyPoints = sections.first { $0.heading == "Key points" }
        #expect(keyPoints?.lines == ["Budget:", "- a", "Schedule:", "- b"])
        #expect(ExportRenderer.plainText(for: document).contains("KEY POINTS\nBudget:\n• a\nSchedule:\n• b"))
    }
}
