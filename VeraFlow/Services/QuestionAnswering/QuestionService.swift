import Foundation

/// What the model returns for a question, before validation.
struct RawAnswer: Sendable, Equatable {
    var answer: String
    /// "mm:ss" strings as the model wrote them.
    var citations: [String]
    var foundInTranscript: Bool
}

/// A validated answer (v1.1 plan item 11): either grounded in retrieved lines with at least
/// one citation that lands inside them, or "not found" with the closest lines to read.
enum ValidatedAnswer: Equatable, Sendable {
    case answered(text: String, citations: [TimeInterval])
    case notFound(closest: [RetrievablePassage])
}

/// Mechanical grounding: the answer shows only when the model says it found it and at least
/// one citation falls inside a passage it was given. Everything else is "not found".
enum AnswerValidator {
    static func validate(_ raw: RawAnswer, retrieved: [RetrievablePassage]) -> ValidatedAnswer {
        let text = TextSanitizer.stripLinksAndMarkupKeepingLines(raw.answer).trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.foundInTranscript, !text.isEmpty, !retrieved.isEmpty else {
            return .notFound(closest: Array(retrieved.prefix(3)))
        }
        var valid: [TimeInterval] = []
        for citation in raw.citations {
            guard let time = ActionItemPostProcessor.parseTimestamp(citation) else { continue }
            if let passage = retrieved.first(where: { $0.start - 1 <= time && time < max($0.end, $0.start + 1) + 1 }) {
                if !valid.contains(passage.start) { valid.append(passage.start) }
            }
        }
        guard !valid.isEmpty else { return .notFound(closest: Array(retrieved.prefix(3))) }
        return .answered(text: text, citations: valid.sorted())
    }
}

/// Answers a question from transcript excerpts with the on-device model (v1.1 plan item 11).
/// `LiveQuestionService` is the real one. Retrieval and validation happen outside, in Swift.
protocol QuestionService: Sendable {
    func availability() async -> SummarizationAvailability
    /// Tokens the excerpts may use in one call.
    func excerptBudgetTokens() async -> Int
    func answer(question: String, excerpts: [TranscriptLine]) async throws -> RawAnswer
}

/// Answers with the first excerpt, citing its time.
actor FakeQuestionService: QuestionService {
    var availabilityToReport: SummarizationAvailability = .available
    var budget = 2_000
    var errorToThrow: SummarizationError?
    /// When set, returned instead of the built answer.
    var cannedAnswer: RawAnswer?
    private(set) var questions: [(question: String, excerpts: [TranscriptLine])] = []

    func availability() async -> SummarizationAvailability { availabilityToReport }

    func excerptBudgetTokens() async -> Int { budget }

    func answer(question: String, excerpts: [TranscriptLine]) async throws -> RawAnswer {
        if let errorToThrow { throw errorToThrow }
        questions.append((question, excerpts))
        if let cannedAnswer { return cannedAnswer }
        guard let first = excerpts.first else {
            return RawAnswer(answer: "", citations: [], foundInTranscript: false)
        }
        return RawAnswer(answer: first.text, citations: [TranscriptChunker.timestamp(first.start)], foundInTranscript: true)
    }

    func setCannedAnswer(_ answer: RawAnswer?) { cannedAnswer = answer }
    func setError(_ error: SummarizationError?) { errorToThrow = error }
    func setAvailability(_ availability: SummarizationAvailability) { availabilityToReport = availability }
    func setBudget(_ tokens: Int) { budget = tokens }
}
