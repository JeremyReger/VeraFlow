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

/// One question and the answer it got, kept with the recording so the Ask tab still has them
/// after you leave it. A "not found" answer is stored with empty text; its closest lines are
/// not, because they are a view of the transcript that asking again rebuilds.
struct StoredAskExchange: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var question: String
    /// Empty when the recording didn't answer the question.
    var answer: String
    var citations: [TimeInterval]

    init(id: UUID = UUID(), question: String, answer: String, citations: [TimeInterval] = []) {
        self.id = id
        self.question = question
        self.answer = answer
        self.citations = citations
    }

    var wasAnswered: Bool { !answer.isEmpty }
}

/// The exchange just before this question, so a follow-up ("who said that?", "when?") has
/// something to resolve against. Only an answered exchange makes one.
struct AskContext: Sendable, Equatable {
    var question: String
    var answer: String
}

/// The prompt body for one question: the excerpts, the previous exchange when this is a
/// follow-up, then the question itself. Every piece of user or model text is sanitized, so
/// nothing inside it can read as an instruction (security review S-14).
enum AskPrompt {
    static func text(excerpts: [TranscriptLine], question: String, context: AskContext?) -> String {
        var parts = ["Excerpts:\n" + TranscriptChunker.text(for: excerpts)]
        if let context {
            parts.append(
                "The previous question was: " + FocusLine.sanitize(context.question)
                + "\nThe previous answer was: " + FocusLine.sanitize(context.answer)
                + "\nThe question below may refer back to them."
            )
        }
        parts.append("Question: " + FocusLine.sanitize(question))
        return parts.joined(separator: "\n\n")
    }
}

/// Answers a question from transcript excerpts with the on-device model (v1.1 plan item 11).
/// `LiveQuestionService` is the real one. Retrieval and validation happen outside, in Swift.
protocol QuestionService: Sendable {
    func availability() async -> SummarizationAvailability
    /// Tokens the excerpts may use in one call.
    func excerptBudgetTokens() async -> Int
    /// `context` is the previous exchange when this question is a follow-up, else `nil`.
    func answer(question: String, excerpts: [TranscriptLine], context: AskContext?) async throws -> RawAnswer
}

/// Answers with the first excerpt, citing its time.
actor FakeQuestionService: QuestionService {
    var availabilityToReport: SummarizationAvailability = .available
    var budget = 2_000
    var errorToThrow: SummarizationError?
    /// When set, returned instead of the built answer.
    var cannedAnswer: RawAnswer?
    private(set) var questions: [(question: String, excerpts: [TranscriptLine], context: AskContext?)] = []

    func availability() async -> SummarizationAvailability { availabilityToReport }

    func excerptBudgetTokens() async -> Int { budget }

    func answer(question: String, excerpts: [TranscriptLine], context: AskContext?) async throws -> RawAnswer {
        if let errorToThrow { throw errorToThrow }
        questions.append((question, excerpts, context))
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
