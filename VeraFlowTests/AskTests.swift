import Foundation
import Testing
@testable import VeraFlow

/// "Ask this recording" (v1.1 plan item 11): retrieval, validation, and the controller on the fake.
@MainActor
struct AskTests {
    private let passages: [RetrievablePassage] = [
        RetrievablePassage(index: 0, start: 0, end: 20, speakerKey: "S1", speakerDisplayName: "Jeremy", text: "Welcome. Let's start with the budget for next quarter."),
        RetrievablePassage(index: 1, start: 20, end: 45, speakerKey: "S2", speakerDisplayName: "Dave", text: "The permit has to be in hand before we pour the footer."),
        RetrievablePassage(index: 2, start: 45, end: 70, speakerKey: "S1", speakerDisplayName: "Jeremy", text: "I'll call the county on Monday about the permit."),
        RetrievablePassage(index: 3, start: 70, end: 90, speakerKey: "S2", speakerDisplayName: "Dave", text: "Tile for the bathroom floor is on back order."),
    ]

    @Test("Tokens drop stopwords; scores favour the passages that share the question's words and the named speaker")
    func ranking() {
        #expect(TranscriptRetriever.tokens("What did Dave say about the permit?") == ["dave", "permit"])
        let scores = TranscriptRetriever.scores(question: "What did Dave say about the permit?", passages: passages)
        #expect(scores[1] > scores[2], "Dave's permit line beats Jeremy's")
        #expect(scores[2] > 0)
        #expect(scores[0] == 0)
        #expect(scores[3] > 0, "Dave's name matches even without the subject")
        #expect(TranscriptRetriever.scores(question: "?", passages: passages).allSatisfy { $0 == 0 })
    }

    @Test("Selection takes the best passages with their neighbours, in order, within the budget; no match selects nothing")
    func selection() {
        let selected = TranscriptRetriever.select(question: "tile back order", passages: passages, budgetTokens: 10_000)
        #expect(selected.map(\.index) == [2, 3], "the match and its earlier neighbour, in transcript order")
        let tight = TranscriptRetriever.select(question: "tile back order", passages: passages, budgetTokens: 30, tokenCount: { _ in 20 })
        #expect(tight.map(\.index) == [3], "no room for the neighbour")
        #expect(TranscriptRetriever.select(question: "parking", passages: passages, budgetTokens: 10_000).isEmpty)
        #expect(TranscriptRetriever.select(question: "permit", passages: passages, budgetTokens: 0).isEmpty)
    }

    @Test("An answer shows only with a citation inside a retrieved passage; anything else is not found")
    func validation() {
        let retrieved = Array(passages[1...2])
        let good = RawAnswer(answer: "The permit must be in hand before the footer is poured. [x](http://a.b)", citations: ["00:25", "09:00"], foundInTranscript: true)
        #expect(AnswerValidator.validate(good, retrieved: retrieved) == .answered(text: "The permit must be in hand before the footer is poured. x", citations: [20]))

        let outside = RawAnswer(answer: "Something", citations: ["05:00"], foundInTranscript: true)
        #expect(AnswerValidator.validate(outside, retrieved: retrieved) == .notFound(closest: retrieved))
        let noCitation = RawAnswer(answer: "Something", citations: [], foundInTranscript: true)
        #expect(AnswerValidator.validate(noCitation, retrieved: retrieved) == .notFound(closest: retrieved))
        let notFound = RawAnswer(answer: "Made up", citations: ["00:25"], foundInTranscript: false)
        #expect(AnswerValidator.validate(notFound, retrieved: retrieved) == .notFound(closest: retrieved))
        #expect(AnswerValidator.validate(good, retrieved: []) == .notFound(closest: []))
    }

    @Test("The controller retrieves, asks, validates, and keeps a history; a no-match question never calls the model")
    func controller() async {
        let service = FakeQuestionService()
        let controller = AskController(service: service, passages: passages)
        await controller.ask("What did Dave say about the permit?")
        #expect(controller.exchanges.count == 1)
        guard case .answered(let text, let citations) = controller.exchanges[0].outcome else {
            Issue.record("expected an answer")
            return
        }
        #expect(text == "Welcome. Let's start with the budget for next quarter.", "the fake answers with the first excerpt, which is the neighbour at 0:00")
        #expect(citations == [0])
        #expect(await service.questions.count == 1)
        #expect(await service.questions[0].excerpts.map(\.start) == [0, 20, 45, 70])

        await controller.ask("Was parking discussed?")
        #expect(controller.exchanges[1].outcome == .notFound(closest: []))
        #expect(await service.questions.count == 1, "no model call without a match")

        await service.setError(.rateLimited)
        await controller.ask("permit")
        #expect(controller.exchanges[2].outcome == .failed(SummarizationError.rateLimitedMessage))
        controller.clear()
        #expect(controller.exchanges.isEmpty)
    }

    @Test("Suggestions come from open questions, then generic ones with a named speaker; Ask is unlocked or sample only")
    func suggestionsAndGate() {
        let items = AskController.suggestions(openQuestions: ["Who signs the permit?", " ", "When is the pour?"], speakerNames: ["Speaker 1", "Dana"])
        #expect(items == ["Who signs the permit?", "When is the pour?", "What was decided?", "What did Dana agree to do?"])
        #expect(AskController.suggestions(openQuestions: [], speakerNames: ["Speaker 1"]).last == "Who has to do what next?")
        #expect(!ExportGate.canAsk(unlocked: false, isSample: false))
        #expect(ExportGate.canAsk(unlocked: false, isSample: true))
        #expect(ExportGate.canAsk(unlocked: true, isSample: false))
    }
}
