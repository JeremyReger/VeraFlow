import Foundation
import Observation

/// One question and what came back.
struct AskExchange: Identifiable, Equatable, Sendable {
    enum Outcome: Equatable, Sendable {
        case pending
        case answered(text: String, citations: [TimeInterval])
        case notFound(closest: [RetrievablePassage])
        case failed(String)
    }

    /// Kept across a reload so the list's identity, and the stored history's, stay the same.
    let id: UUID
    var question: String
    var outcome: Outcome

    /// Rebuilt from the stored history; the closest lines of a not-found answer aren't kept.
    init(stored: StoredAskExchange) {
        id = stored.id
        question = stored.question
        outcome = stored.wasAnswered ? .answered(text: stored.answer, citations: stored.citations) : .notFound(closest: [])
    }

    init(id: UUID = UUID(), question: String, outcome: Outcome) {
        self.id = id
        self.question = question
        self.outcome = outcome
    }
}

extension StoredAskExchange {
    /// `nil` for an exchange still running or one that failed: neither is worth keeping.
    init?(_ exchange: AskExchange) {
        switch exchange.outcome {
        case .answered(let text, let citations):
            self.init(id: exchange.id, question: exchange.question, answer: text, citations: citations)
        case .notFound:
            self.init(id: exchange.id, question: exchange.question, answer: "", citations: [])
        case .pending, .failed:
            return nil
        }
    }
}

/// Drives the Ask tab (v1.1 plan item 11): retrieval in Swift, one model call per question,
/// mechanical validation, and the question history kept with the recording.
@Observable
@MainActor
final class AskController {
    private(set) var exchanges: [AskExchange] = []
    private(set) var isWorking = false
    private(set) var availability: SummarizationAvailability?

    private let service: any QuestionService
    private let passages: [RetrievablePassage]

    init(service: any QuestionService, passages: [RetrievablePassage], history: [StoredAskExchange] = []) {
        self.service = service
        self.passages = passages
        exchanges = history.map(AskExchange.init)
    }

    /// What the screen stores on the recording: the finished exchanges, oldest first. A
    /// question still running, or one that failed, isn't kept.
    var storedHistory: [StoredAskExchange] {
        exchanges.compactMap(StoredAskExchange.init)
    }

    func refreshAvailability() async {
        availability = await service.availability()
    }

    /// Passages from a recording's paragraphs with the speakers' current names.
    static func passages(segments: [(index: Int, start: TimeInterval, end: TimeInterval, speakerKey: String?, text: String)], speakerNames: [String: String]) -> [RetrievablePassage] {
        segments.map { segment in
            RetrievablePassage(
                index: segment.index,
                start: segment.start,
                end: segment.end,
                speakerKey: segment.speakerKey,
                speakerDisplayName: segment.speakerKey.flatMap { speakerNames[$0] } ?? segment.speakerKey.map(SpokenFormat.speakerName(forKey:)) ?? "Speaker",
                text: segment.text
            )
        }
    }

    /// Suggested questions from the summary: its open questions first, then two generic ones.
    static func suggestions(openQuestions: [String], speakerNames: [String]) -> [String] {
        var result = openQuestions.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.prefix(3).map { String($0) }
        result.append("What was decided?")
        if let first = speakerNames.first(where: { !TranscriptTab.isDefaultName($0) }) {
            result.append("What did \(first) agree to do?")
        } else {
            result.append("Who has to do what next?")
        }
        return result
    }

    /// Whether the Ask button does anything: a question with more than whitespace, and no
    /// answer already on its way. The same rule `ask(_:)` guards itself with.
    static func canSend(question: String, isWorking: Bool) -> Bool {
        !isWorking && !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The most recent answered exchange before `position`. A not-found or failed one carries
    /// nothing a follow-up could refer back to, so it is skipped.
    static func context(in exchanges: [AskExchange], before position: Int) -> AskContext? {
        for exchange in exchanges[..<min(position, exchanges.count)].reversed() {
            if case .answered(let text, _) = exchange.outcome {
                return AskContext(question: exchange.question, answer: text)
            }
        }
        return nil
    }

    /// A question with no words of its own to match ("who said that?", "when?") only means
    /// something beside the answer before it. Anything with a subject of its own is a new
    /// question, and a new question that matches nothing is honestly not found.
    static func isFollowUp(question: String) -> Bool {
        TranscriptRetriever.tokens(question).isEmpty
    }

    /// What to retrieve on for a follow-up: the previous exchange supplies the words the
    /// question itself doesn't have.
    static func followUpQuery(question: String, context: AskContext) -> String {
        [context.question, context.answer, question].joined(separator: " ")
    }

    /// One exchange as text to paste elsewhere: the question, the answer, and the moments it
    /// cites. Nothing is copied for a question the recording couldn't answer.
    static func copyText(for exchange: AskExchange) -> String? {
        guard case .answered(let text, let citations) = exchange.outcome else { return nil }
        var lines = [exchange.question, "", text]
        if !citations.isEmpty {
            lines.append("")
            lines.append("Moments: " + citations.map(TranscriptChunker.timestamp).joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }

    func ask(_ question: String) async {
        let cleaned = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        var exchange = AskExchange(question: cleaned, outcome: .pending)
        exchanges.append(exchange)
        let position = exchanges.count - 1

        let budget = await service.excerptBudgetTokens()
        let context = Self.context(in: exchanges, before: position)
        var retrieved = TranscriptRetriever.select(question: cleaned, passages: passages, budgetTokens: budget)
        if retrieved.isEmpty, let context, Self.isFollowUp(question: cleaned) {
            retrieved = TranscriptRetriever.select(
                question: Self.followUpQuery(question: cleaned, context: context),
                passages: passages,
                budgetTokens: budget
            )
        }
        guard !retrieved.isEmpty else {
            exchange.outcome = .notFound(closest: [])
            exchanges[position] = exchange
            return
        }
        do {
            let raw = try await service.answer(
                question: cleaned,
                excerpts: TranscriptRetriever.lines(for: retrieved),
                context: context
            )
            switch AnswerValidator.validate(raw, retrieved: retrieved) {
            case .answered(let text, let citations):
                exchange.outcome = .answered(text: text, citations: citations)
            case .notFound(let closest):
                exchange.outcome = .notFound(closest: closest)
            }
        } catch {
            exchange.outcome = .failed(PipelineFailure.message(for: error))
        }
        exchanges[position] = exchange
    }

    func clear() {
        exchanges = []
    }
}
