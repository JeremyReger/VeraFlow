import Foundation
import FoundationModels
import os

@available(iOS 26, *)
@Generable(description: "An answer drawn only from the transcript excerpts given.")
struct GroundedAnswerGenerable {
    @Guide(description: "The answer in one to three sentences, using only what the excerpts say. Empty if the excerpts don't answer the question.")
    var answer: String
    @Guide(description: "Timestamps mm:ss or h:mm:ss of the excerpt lines the answer relies on. Empty if none.")
    var citations: [String]
    @Guide(description: "True only if the excerpts actually answer the question.")
    var foundInTranscript: Bool
}

/// "Ask this recording" with Apple's on-device model (v1.1 plan item 11): a fresh session per
/// question, the retrieved lines as the prompt, and a small typed answer. Same error handling
/// as the summarizer.
@available(iOS 26, *)
actor LiveQuestionService: QuestionService {
    private static let log = Logger(subsystem: "com.jeremyreger.veraflow", category: "ask")
    private static let schemaOverheadEstimate = 250
    private static let fallbackContextSize = 4_096

    private var model: SystemLanguageModel { .default }

    func availability() async -> SummarizationAvailability {
        switch model.availability {
        case .available: return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return .deviceNotEligible
            case .appleIntelligenceNotEnabled: return .appleIntelligenceNotEnabled
            case .modelNotReady: return .modelNotReady
            @unknown default: return .unknown(String(describing: reason))
            }
        }
    }

    func excerptBudgetTokens() async -> Int {
        var contextSize = model.contextSize
        if contextSize < 1_024 { contextSize = Self.fallbackContextSize }
        let instructions = TranscriptChunker.estimateTokens(Prompts.instructions(Prompts.ask))
        return ContextBudget(contextSize: contextSize, instructionsTokens: instructions + 60, schemaOverhead: Self.schemaOverheadEstimate, outputReserve: 400).inputTokens
    }

    func answer(question: String, excerpts: [TranscriptLine], context: AskContext?) async throws -> RawAnswer {
        let availability = await availability()
        guard availability.isAvailable else { throw SummarizationError.unavailable(availability) }
        let session = LanguageModelSession(instructions: Prompts.instructions(Prompts.ask))
        let body = AskPrompt.text(excerpts: excerpts, question: question, context: context)
        let prompt = Prompt { body }
        do {
            let content = try await session.respond(
                to: prompt,
                generating: GroundedAnswerGenerable.self,
                options: GenerationOptions(sampling: nil, temperature: 0.2, maximumResponseTokens: nil)
            ).content
            return RawAnswer(answer: content.answer, citations: content.citations, foundInTranscript: content.foundInTranscript)
        } catch is CancellationError {
            throw SummarizationError.cancelled
        } catch let error as SummarizationError {
            throw error
        } catch {
            let kind = LiveSummarizationService.kind(of: error)
            Self.log.notice("ask failed (\(String(describing: kind), privacy: .public))")
            throw LiveSummarizationService.map(error, kind: kind)
        }
    }
}
