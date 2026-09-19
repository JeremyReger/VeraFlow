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

    let id = UUID()
    var question: String
    var outcome: Outcome
}

/// Drives the Ask tab (v1.1 plan item 11): retrieval in Swift, one model call per question,
/// mechanical validation, and an in-memory history for the recording.
@Observable
@MainActor
final class AskController {
    private(set) var exchanges: [AskExchange] = []
    private(set) var isWorking = false
    private(set) var availability: SummarizationAvailability?

    private let service: any QuestionService
    private let passages: [RetrievablePassage]

    init(service: any QuestionService, passages: [RetrievablePassage]) {
        self.service = service
        self.passages = passages
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

    func ask(_ question: String) async {
        let cleaned = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        var exchange = AskExchange(question: cleaned, outcome: .pending)
        exchanges.append(exchange)
        let position = exchanges.count - 1

        let budget = await service.excerptBudgetTokens()
        let retrieved = TranscriptRetriever.select(question: cleaned, passages: passages, budgetTokens: budget)
        guard !retrieved.isEmpty else {
            exchange.outcome = .notFound(closest: [])
            exchanges[position] = exchange
            return
        }
        do {
            let raw = try await service.answer(question: cleaned, excerpts: TranscriptRetriever.lines(for: retrieved))
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
