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

    @Test("A follow-up with no words of its own retrieves on the previous exchange and carries it to the model")
    func followUp() async {
        let service = FakeQuestionService()
        let controller = AskController(service: service, passages: passages)
        await controller.ask("What did Dave say about the permit?")
        #expect(await service.questions.count == 1)
        #expect(await service.questions[0].context == nil, "the first question has nothing before it")

        await controller.ask("Who said that?")
        #expect(await service.questions.count == 2, "the previous exchange supplied the words to retrieve on")
        let context = await service.questions[1].context
        #expect(context?.question == "What did Dave say about the permit?")
        #expect(context?.answer == "Welcome. Let's start with the budget for next quarter.")
        if case .notFound = controller.exchanges[1].outcome {
            Issue.record("the follow-up should have been answered")
        }

        // A question with a subject of its own is not a follow-up: no match still means not found.
        await controller.ask("Was parking discussed?")
        #expect(controller.exchanges[2].outcome == .notFound(closest: []))
        #expect(await service.questions.count == 2, "no model call for a real question that matches nothing")
    }

    @Test("Follow-ups are the questions with no words of their own; the query adds the previous exchange")
    func followUpRules() {
        #expect(AskController.isFollowUp(question: "Who said that?"))
        #expect(AskController.isFollowUp(question: "When?"))
        #expect(!AskController.isFollowUp(question: "Was parking discussed?"))
        #expect(!AskController.isFollowUp(question: "What about the permit?"))

        let context = AskContext(question: "Who signs the permit?", answer: "Dave does.")
        #expect(AskController.followUpQuery(question: "When?", context: context) == "Who signs the permit? Dave does. When?")

        let answered = AskExchange(question: "Q1", outcome: .answered(text: "A1", citations: [5]))
        let missed = AskExchange(question: "Q2", outcome: .notFound(closest: []))
        let pending = AskExchange(question: "Q3", outcome: .pending)
        #expect(AskController.context(in: [answered, missed, pending], before: 3) == AskContext(question: "Q1", answer: "A1"))
        #expect(AskController.context(in: [answered], before: 0) == nil, "nothing before the first question")
        #expect(AskController.context(in: [missed, pending], before: 2) == nil, "only an answer can be referred back to")
    }

    @Test("The history is kept with the recording: finished exchanges only, newest kept, and it rebuilds")
    func storedHistory() async {
        let service = FakeQuestionService()
        let controller = AskController(service: service, passages: passages)
        await controller.ask("What did Dave say about the permit?")
        await controller.ask("Was parking discussed?")
        await service.setError(.rateLimited)
        await controller.ask("permit")

        let stored = controller.storedHistory
        #expect(stored.count == 2, "the failed question is not kept")
        #expect(stored[0].wasAnswered)
        #expect(stored[0].citations == [0])
        #expect(!stored[1].wasAnswered, "not found is kept as a question with no answer")

        let recording = PreviewData.sampleRecording()
        recording.storeAskHistory(stored)
        #expect(recording.askHistory() == stored)

        // Seeding a new controller brings the questions back, ids and all.
        let reopened = AskController(service: FakeQuestionService(), passages: passages, history: recording.askHistory())
        #expect(reopened.exchanges.map(\.id) == stored.map(\.id))
        #expect(reopened.exchanges[0].outcome == .answered(text: stored[0].answer, citations: [0]))
        #expect(reopened.exchanges[1].outcome == .notFound(closest: []))
        #expect(reopened.storedHistory == stored)

        // Only the most recent are kept, and clearing empties the field rather than storing "[]".
        let many = (0..<60).map { StoredAskExchange(question: "Q\($0)", answer: "A\($0)") }
        recording.storeAskHistory(many)
        #expect(recording.askHistory().count == Recording.askHistoryLimit)
        #expect(recording.askHistory().first?.question == "Q10")
        recording.storeAskHistory([])
        #expect(recording.askHistoryJSON == nil)
        #expect(recording.askHistory().isEmpty)
    }

    @Test("An answer copies as the question, the answer, and the moments it cites; nothing else copies")
    func copyText() {
        let answered = AskExchange(question: "Who signs the permit?", outcome: .answered(text: "Dave does.", citations: [65, 20]))
        #expect(AskController.copyText(for: answered) == "Who signs the permit?\n\nDave does.\n\nMoments: 1:05, 0:20")
        let noCitation = AskExchange(question: "Q", outcome: .answered(text: "A", citations: []))
        #expect(AskController.copyText(for: noCitation) == "Q\n\nA")
        #expect(AskController.copyText(for: AskExchange(question: "Q", outcome: .notFound(closest: []))) == nil)
        #expect(AskController.copyText(for: AskExchange(question: "Q", outcome: .pending)) == nil)
    }

    @Test("The prompt carries the excerpts, the previous exchange when there is one, and the question")
    func promptText() {
        let excerpts = [TranscriptLine(start: 20, speakerKey: "S2", speakerDisplayName: "Dave", text: "The permit first.")]
        let plain = AskPrompt.text(excerpts: excerpts, question: "Who signs it?", context: nil)
        #expect(plain.hasPrefix("Excerpts:\n"))
        #expect(plain.contains("The permit first."))
        #expect(plain.hasSuffix("Question: Who signs it?"))
        #expect(!plain.contains("previous"))

        let withContext = AskPrompt.text(
            excerpts: excerpts,
            question: "When?",
            context: AskContext(question: "Who signs the permit?", answer: "Dave does. http://example.com")
        )
        #expect(withContext.contains("The previous question was: Who signs the permit?"))
        #expect(withContext.contains("The previous answer was: Dave does."))
        #expect(!withContext.contains("http"), "model text is sanitized before it goes back in")
        #expect(withContext.hasSuffix("Question: When?"))
    }

    @Test("The Ask button sends only a real question, and never while an answer is on its way")
    func canSend() {
        #expect(AskController.canSend(question: "What was decided?", isWorking: false))
        #expect(!AskController.canSend(question: "", isWorking: false))
        #expect(!AskController.canSend(question: "   \n ", isWorking: false))
        #expect(!AskController.canSend(question: "What was decided?", isWorking: true))
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
