import Foundation
import FoundationModels
import os

// MARK: - Generable drafts (SPEC §11.4)
// Kept separate from the Codable payload types so SwiftData never depends on FoundationModels.

@Generable(description: "One task someone agreed to do.")
struct ActionItemDraftGenerable {
    @Guide(description: "The task, starting with a verb. One sentence.")
    var task: String
    @Guide(description: "Person responsible, exactly as named in the transcript, e.g. 'Speaker 2' or a first name. Empty if not stated.")
    var owner: String
    @Guide(description: "Due date phrase exactly as spoken, e.g. 'next Friday', 'by the 30th'. Empty if none was said. Do not invent dates.")
    var dueText: String
    @Guide(description: "Timestamp mm:ss or h:mm:ss of the line where this was said.")
    var timestamp: String
}

@Generable(description: "Notes extracted from one part of a transcript.")
struct ChunkNotesGenerable {
    @Guide(description: "Key points discussed, max 6, each under 20 words.")
    var keyPoints: [String]
    @Guide(description: "Decisions actually agreed on. Empty if none.")
    var decisions: [String]
    var actionItems: [ActionItemDraftGenerable]
    @Guide(description: "Unresolved questions. Empty if none.")
    var openQuestions: [String]
}

@Generable(description: "Summary of a general meeting or lecture.")
struct GeneralSummaryGenerable {
    @Guide(description: "Short title, max 8 words.")
    var title: String
    @Guide(description: "3–5 sentence overview.")
    var overview: String
    var keyPoints: [String]
    var decisions: [String]
    var actionItems: [ActionItemDraftGenerable]
    var openQuestions: [String]
}

@Generable(description: "Summary of a meeting between a consultant and a client.")
struct ClientMeetingSummaryGenerable {
    @Guide(description: "Short title, max 8 words.")
    var title: String
    @Guide(description: "3–5 sentence overview.")
    var overview: String
    @Guide(description: "What the client wants to achieve, in their words where possible.")
    var clientGoals: [String]
    @Guide(description: "Concerns, objections, budget or timeline constraints the client raised.")
    var concerns: [String]
    var decisions: [String]
    var actionItems: [ActionItemDraftGenerable]
    @Guide(description: "Next meeting or check-in if mentioned, else empty.")
    var nextMeeting: String
    var openQuestions: [String]
}

@Generable(description: "A follow-up email to the client.")
struct FollowUpEmailGenerable {
    var subject: String
    var body: String
}

@Generable(description: "A measurement spoken on site.")
struct MeasurementGenerable {
    @Guide(description: "What was measured, e.g. 'Kitchen wall, north'.")
    var item: String
    @Guide(description: "The value exactly as spoken, e.g. '12 ft 4 in'. Never estimate or convert.")
    var value: String
}

@Generable(description: "A material mentioned for the job.")
struct MaterialGenerable {
    var name: String
    var quantity: String
    var notes: String
}

@Generable(description: "One room or area of the job.")
struct WorkAreaGenerable {
    @Guide(description: "Room or area name, e.g. 'Master bath'.")
    var name: String
    @Guide(description: "Work to be done in this area.")
    var tasks: [String]
    @Guide(description: "Only measurements explicitly spoken. Never estimate or convert.")
    var measurements: [MeasurementGenerable]
    var materials: [MaterialGenerable]
}

@Generable(description: "Summary of a contractor walking a job site with a customer.")
struct WalkthroughSummaryGenerable {
    @Guide(description: "Short title, max 8 words.")
    var title: String
    @Guide(description: "Job address or location if spoken, else empty.")
    var location: String
    @Guide(description: "3–5 sentence overview.")
    var overview: String
    var areas: [WorkAreaGenerable]
    @Guide(description: "Specific customer requests or preferences (colors, brands, finishes).")
    var customerRequests: [String]
    @Guide(description: "Problems found: damage, code, safety, access issues.")
    var issuesFound: [String]
    @Guide(description: "Notes useful for writing the quote: scope, exclusions, permits, timeline.")
    var quoteNotes: [String]
    var actionItems: [ActionItemDraftGenerable]
}

// MARK: - Service

/// Template summaries with Apple's on-device model (SPEC §11). Map-reduce over transcript chunks
/// sized from the model's context size, read at runtime; a fresh `LanguageModelSession` for every
/// call; the deterministic post-processing happens in the pipeline, not here.
///
/// Verified against the Foundation Models docs on 2026-09-18: `SystemLanguageModel.default.availability`,
/// `contextSize` (back-deployed to iOS 26.0), `tokenCount(for:)` (iOS 26.4+), `LanguageModelSession(instructions: String?)`,
/// `respond(to:generating:options:)`, `prewarm(promptPrefix:)`, `GenerationOptions(sampling:temperature:maximumResponseTokens:)`,
/// `LanguageModelSession.GenerationError` (deprecated in the iOS 27 SDK in favour of `LanguageModelError`; see DECISIONS).
actor LiveSummarizationService: SummarizationService {
    private static let log = Logger(subsystem: "com.jeremyreger.veraflow", category: "summaries")

    /// Tokens the JSON schema of the largest output type costs when the model can't count them.
    private static let schemaOverheadEstimate = 600
    /// How many times to shrink the chunks after the model reports a context overflow.
    private static let maxOverflowRetries = 3
    /// SPEC §11.2's iOS 26 figure, used only when the model can't report its context size
    /// (it returns 0 while the system is rate limiting metadata lookups).
    private static let fallbackContextSize = 4_096
    /// Back-off before retrying a rate-limited request, per attempt.
    private static let rateLimitDelays: [Duration] = [.seconds(10), .seconds(30)]

    private var model: SystemLanguageModel { .default }
    /// Instruction/schema token counts don't change per launch; counting them costs model
    /// requests, which is exactly what the system rate-limits.
    private var budgetCache: [TemplateID: ContextBudget] = [:]

    // MARK: SummarizationService

    func availability() async -> SummarizationAvailability {
        switch model.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return .deviceNotEligible
            case .appleIntelligenceNotEnabled: return .appleIntelligenceNotEnabled
            case .modelNotReady: return .modelNotReady
            @unknown default: return .unknown(String(describing: reason))
            }
        }
    }

    func prewarm() async {
        guard case .available = model.availability else { return }
        LanguageModelSession(instructions: Prompts.instructions(Prompts.map)).prewarm()
    }

    func modelInfo() async -> String {
        "SystemLanguageModel iOS \(ProcessInfo.processInfo.operatingSystemVersionString) · context \(model.contextSize)"
    }

    func summarize(
        _ input: SummarizationInput,
        progress: @Sendable @escaping (SummarizationProgress) -> Void
    ) async throws -> SummaryPayload {
        let availability = await availability()
        guard availability.isAvailable else { throw SummarizationError.unavailable(availability) }
        guard !input.lines.isEmpty else { throw SummarizationError.generationFailed("The transcript is empty.") }

        let budget = try await makeBudget(for: input.template)
        var inputTokens = budget.inputTokens
        let counter = await tokenCounter(calibratedOn: TranscriptChunker.text(for: input.lines))

        var rateLimitWaits = 0
        for attempt in 0...Self.maxOverflowRetries {
            do {
                return try await run(input, inputTokens: inputTokens, tokenCount: counter, progress: progress)
            } catch let error as LanguageModelSession.GenerationError {
                if case .rateLimited = error {
                    // The system throttles the model (often for minutes). Wait briefly twice, then
                    // hand back `.rateLimited` so the pipeline retries later instead of failing.
                    guard rateLimitWaits < Self.rateLimitDelays.count else { throw SummarizationError.rateLimited }
                    let delay = Self.rateLimitDelays[rateLimitWaits]
                    rateLimitWaits += 1
                    Self.log.notice("model rate limited; retrying in \(delay.description, privacy: .public)")
                    try await Task.sleep(for: delay)
                    continue
                }
                guard case .exceededContextWindowSize = error, attempt < Self.maxOverflowRetries else {
                    throw Self.map(error)
                }
                // Only the chunk size shrinks (SPEC §11.2); the reserve stays.
                inputTokens = ContextBudget.shrunk(inputTokens)
                Self.log.notice("context overflow; retrying with \(inputTokens, privacy: .public)-token chunks")
            } catch is CancellationError {
                throw SummarizationError.cancelled
            } catch let error as SummarizationError {
                throw error
            } catch {
                throw SummarizationError.generationFailed(error.localizedDescription)
            }
        }
        throw SummarizationError.contextOverflow
    }

    func followUpEmail(for summary: ClientMeetingSummary) async throws -> FollowUpEmail {
        let availability = await availability()
        guard availability.isAvailable else { throw SummarizationError.unavailable(availability) }
        let session = LanguageModelSession(instructions: Prompts.instructions(Prompts.followUpEmail))
        do {
            let response = try await session.respond(
                to: Prompt { Self.render(summary) },
                generating: FollowUpEmailGenerable.self,
                options: Self.options
            )
            return FollowUpEmail(subject: response.content.subject, body: response.content.body)
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.map(error)
        } catch is CancellationError {
            throw SummarizationError.cancelled
        } catch {
            throw SummarizationError.generationFailed(error.localizedDescription)
        }
    }

    // MARK: Map-reduce

    private static let options = GenerationOptions(sampling: nil, temperature: 0.25, maximumResponseTokens: nil)

    private func run(
        _ input: SummarizationInput,
        inputTokens: Int,
        tokenCount: @escaping (String) -> Int,
        progress: @Sendable @escaping (SummarizationProgress) -> Void
    ) async throws -> SummaryPayload {
        let template = input.template
        if TranscriptChunker.fitsInOneCall(input.lines, budgetTokens: inputTokens, tokenCount: tokenCount) {
            progress(SummarizationProgress(completedChunks: 0, totalChunks: 1))
            let payload = try await final(from: TranscriptChunker.text(for: input.lines), template: template, fromTranscript: true)
            progress(SummarizationProgress(completedChunks: 1, totalChunks: 1))
            return payload
        }

        let chunks = TranscriptChunker.chunks(lines: input.lines, budgetTokens: inputTokens, tokenCount: tokenCount)
        var completed = 0
        var total = chunks.count + 1
        progress(SummarizationProgress(completedChunks: 0, totalChunks: total))
        Self.log.info("map over \(chunks.count, privacy: .public) chunks of ≤\(inputTokens, privacy: .public) tokens")

        var notes: [String] = []
        for chunk in chunks {
            try Task.checkCancellation()
            let result = try await mapChunk(chunk.text)
            notes.append(Self.render(result))
            completed += 1
            progress(SummarizationProgress(completedChunks: completed, totalChunks: total))
        }

        // REDUCE: while the notes don't fit one call, combine them in groups (SPEC §11.3).
        var combined = notes.joined(separator: "\n\n")
        while tokenCount(combined) > inputTokens, notes.count > 1 {
            try Task.checkCancellation()
            let groups = Self.group(notes, budgetTokens: inputTokens, tokenCount: tokenCount)
            total += groups.count
            progress(SummarizationProgress(completedChunks: completed, totalChunks: total))
            var reduced: [String] = []
            for group in groups {
                try Task.checkCancellation()
                let result = try await mapChunk(group.joined(separator: "\n\n"))
                reduced.append(Self.render(result))
                completed += 1
                progress(SummarizationProgress(completedChunks: completed, totalChunks: total))
            }
            guard reduced.count < notes.count else { break } // no progress possible; let the final call decide
            notes = reduced
            combined = notes.joined(separator: "\n\n")
        }

        let payload = try await final(from: combined, template: template, fromTranscript: false)
        completed += 1
        progress(SummarizationProgress(completedChunks: completed, totalChunks: total))
        return payload
    }

    private func mapChunk(_ text: String) async throws -> ChunkNotesGenerable {
        let session = LanguageModelSession(instructions: Prompts.instructions(Prompts.map))
        return try await session.respond(to: Prompt { text }, generating: ChunkNotesGenerable.self, options: Self.options).content
    }

    private func final(from text: String, template: TemplateID, fromTranscript: Bool) async throws -> SummaryPayload {
        let step = fromTranscript ? Prompts.finalFromTranscript(for: template) : Prompts.final(for: template)
        let session = LanguageModelSession(instructions: Prompts.instructions(step))
        let prompt = Prompt { text }
        switch template {
        case .general:
            let content = try await session.respond(to: prompt, generating: GeneralSummaryGenerable.self, options: Self.options).content
            return .general(GeneralSummary(
                title: content.title,
                overview: content.overview,
                keyPoints: content.keyPoints,
                decisions: content.decisions,
                actionItems: content.actionItems.map(Self.actionItem),
                openQuestions: content.openQuestions
            ))
        case .client:
            let content = try await session.respond(to: prompt, generating: ClientMeetingSummaryGenerable.self, options: Self.options).content
            return .client(ClientMeetingSummary(
                title: content.title,
                overview: content.overview,
                clientGoals: content.clientGoals,
                concerns: content.concerns,
                decisions: content.decisions,
                actionItems: content.actionItems.map(Self.actionItem),
                nextMeeting: content.nextMeeting,
                openQuestions: content.openQuestions
            ))
        case .walkthrough:
            let content = try await session.respond(to: prompt, generating: WalkthroughSummaryGenerable.self, options: Self.options).content
            return .walkthrough(WalkthroughSummary(
                title: content.title,
                location: content.location,
                overview: content.overview,
                areas: content.areas.map { area in
                    WorkArea(
                        name: area.name,
                        tasks: area.tasks,
                        measurements: area.measurements.map { Measurement(item: $0.item, value: $0.value, timestamp: nil) },
                        materials: area.materials.map { Material(name: $0.name, quantity: $0.quantity, notes: $0.notes) }
                    )
                },
                customerRequests: content.customerRequests,
                issuesFound: content.issuesFound,
                quoteNotes: content.quoteNotes,
                actionItems: content.actionItems.map(Self.actionItem)
            ))
        }
    }

    // MARK: Budget

    /// Context size read from the model at runtime; instruction and schema costs counted by the
    /// model where it can (iOS 26.4+), estimated otherwise (SPEC §11.2).
    private func makeBudget(for template: TemplateID) async throws -> ContextBudget {
        if let cached = budgetCache[template] { return cached }
        var contextSize = model.contextSize
        if contextSize < 1_024 {
            // 0 means the lookup failed (rate limited); don't shrink chunks to nothing.
            Self.log.notice("context size unavailable (\(contextSize, privacy: .public)); assuming \(Self.fallbackContextSize, privacy: .public)")
            contextSize = Self.fallbackContextSize
        }
        let instructions = Prompts.instructions(Prompts.final(for: template))
        var instructionTokens = TranscriptChunker.estimateTokens(instructions)
        var schemaTokens = Self.schemaOverheadEstimate
        if #available(iOS 26.4, *) {
            if let counted = try? await model.tokenCount(for: Instructions { instructions }) {
                instructionTokens = counted
            }
            let schemas: [GenerationSchema] = [ChunkNotesGenerable.generationSchema, Self.finalSchema(for: template)]
            var largest = 0
            for schema in schemas {
                if let counted = try? await model.tokenCount(for: schema) {
                    largest = max(largest, counted)
                }
            }
            if largest > 0 { schemaTokens = largest }
        }
        let budget = ContextBudget(contextSize: contextSize, instructionsTokens: instructionTokens, schemaOverhead: schemaTokens)
        Self.log.info("context \(contextSize, privacy: .public) tokens; instructions \(instructionTokens, privacy: .public); schema \(schemaTokens, privacy: .public); input budget \(budget.inputTokens, privacy: .public)")
        if model.contextSize >= 1_024 {
            budgetCache[template] = budget // only cache counts made with a healthy model
        }
        return budget
    }

    private static func finalSchema(for template: TemplateID) -> GenerationSchema {
        switch template {
        case .general: GeneralSummaryGenerable.generationSchema
        case .client: ClientMeetingSummaryGenerable.generationSchema
        case .walkthrough: WalkthroughSummaryGenerable.generationSchema
        }
    }

    /// The chars ÷ 3.5 estimate, scaled by one real count of the whole transcript when the model
    /// can count tokens, so chunking stays synchronous but tracks the real tokenizer.
    private func tokenCounter(calibratedOn sample: String) async -> @Sendable (String) -> Int {
        var ratio = 1.0
        // Skip the calibration request while the model can't even report its size.
        if #available(iOS 26.4, *), !sample.isEmpty, model.contextSize >= 1_024, let counted = try? await model.tokenCount(for: Prompt { sample }) {
            let estimated = TranscriptChunker.estimateTokens(sample)
            if estimated > 0, counted > 0 {
                ratio = Double(counted) / Double(estimated)
            }
        }
        // Never trust the calibration to be generous: keep at least the conservative estimate.
        let factor = max(ratio, 1.0)
        return { text in Int((Double(TranscriptChunker.estimateTokens(text)) * factor).rounded(.up)) }
    }

    /// Splits notes into consecutive groups that each fit the budget.
    static func group(_ notes: [String], budgetTokens: Int, tokenCount: (String) -> Int) -> [[String]] {
        var groups: [[String]] = []
        var current: [String] = []
        var total = 0
        for note in notes {
            let cost = tokenCount(note) + 1
            if !current.isEmpty, total + cost > budgetTokens {
                groups.append(current)
                current = []
                total = 0
            }
            current.append(note)
            total += cost
        }
        if !current.isEmpty { groups.append(current) }
        // Guarantee progress: at least two notes per group when there are notes to spare.
        if groups.count == notes.count, notes.count > 1 {
            return stride(from: 0, to: notes.count, by: 2).map { Array(notes[$0 ..< min($0 + 2, notes.count)]) }
        }
        return groups
    }

    // MARK: Rendering

    static func actionItem(_ draft: ActionItemDraftGenerable) -> ActionItem {
        ActionItem(
            task: draft.task,
            owner: draft.owner,
            dueText: draft.dueText,
            timestamp: ActionItemPostProcessor.parseTimestamp(draft.timestamp)
        )
    }

    /// Compact text for the REDUCE and FINAL steps.
    static func render(_ notes: ChunkNotesGenerable) -> String {
        var lines: [String] = []
        if !notes.keyPoints.isEmpty {
            lines.append("Key points:")
            lines += notes.keyPoints.map { "- \($0)" }
        }
        if !notes.decisions.isEmpty {
            lines.append("Decisions:")
            lines += notes.decisions.map { "- \($0)" }
        }
        if !notes.actionItems.isEmpty {
            lines.append("Action items:")
            lines += notes.actionItems.map { item in
                var parts = ["- \(item.task)"]
                if !item.owner.isEmpty { parts.append("owner: \(item.owner)") }
                if !item.dueText.isEmpty { parts.append("due: \(item.dueText)") }
                if !item.timestamp.isEmpty { parts.append("at \(item.timestamp)") }
                return parts.joined(separator: "; ")
            }
        }
        if !notes.openQuestions.isEmpty {
            lines.append("Open questions:")
            lines += notes.openQuestions.map { "- \($0)" }
        }
        return lines.joined(separator: "\n")
    }

    static func render(_ summary: ClientMeetingSummary) -> String {
        var lines = ["Title: \(summary.title)", "Overview: \(summary.overview)"]
        func add(_ title: String, _ items: [String]) {
            guard !items.isEmpty else { return }
            lines.append("\(title):")
            lines += items.map { "- \($0)" }
        }
        add("Client goals", summary.clientGoals)
        add("Concerns", summary.concerns)
        add("Decisions", summary.decisions)
        add("Action items", summary.actionItems.map { item in
            [item.task, item.owner.isEmpty ? "" : "owner: \(item.owner)", item.dueText.isEmpty ? "" : "due: \(item.dueText)"]
                .filter { !$0.isEmpty }
                .joined(separator: "; ")
        })
        if !summary.nextMeeting.isEmpty { lines.append("Next meeting: \(summary.nextMeeting)") }
        add("Open questions", summary.openQuestions)
        return lines.joined(separator: "\n")
    }

    // MARK: Errors

    private static func map(_ error: LanguageModelSession.GenerationError) -> SummarizationError {
        switch error {
        case .exceededContextWindowSize:
            return .contextOverflow
        case .assetsUnavailable:
            return .unavailable(.modelNotReady)
        case .guardrailViolation:
            return .generationFailed("The on-device model declined this content (safety guardrails).")
        case .refusal:
            return .generationFailed("The on-device model declined to summarize this recording.")
        case .rateLimited:
            return .rateLimited
        case .decodingFailure:
            return .generationFailed("The model's answer couldn't be read. Try again.")
        case .unsupportedLanguageOrLocale:
            return .generationFailed("The on-device model doesn't support this language yet.")
        default:
            return .generationFailed(error.localizedDescription)
        }
    }
}
