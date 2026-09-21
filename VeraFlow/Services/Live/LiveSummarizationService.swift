import Foundation
import FoundationModels
import os

// MARK: - Generable drafts (SPEC §11.4)
// Kept separate from the Codable payload types so SwiftData never depends on FoundationModels.
//
// Every array carries a `.maximumCount` guide. A count written only in the description is a
// suggestion the model is free to ignore, and on Jeremy's 1:58 recording it did: the answer
// cycled the same six topics nineteen times until it ran out of window and the JSON was cut off
// mid-string, which came back as a decoding failure. `.maximumCount` is enforced by constrained
// decoding, so the loop can't start (2026-09-19).
//
// No description carries an example value. A guide reading "e.g. '12 ft 4 in'" put that string
// into the answer: on a 35-second, 117-word recording the walkthrough template returned ten rooms
// and twenty measurements, and "Kitchen wall, north", "12 ft 4 in" and "Master bath" — the three
// example values these descriptions used to carry — appeared in every attempt. The model reads
// the schema as part of its context, so an example in it is something to copy when there is
// nothing real to say. Describe the shape; never show a value (2026-09-20).

@available(iOS 26, *)
@Generable(description: "One task someone agreed to do.")
struct ActionItemDraftGenerable {
    @Guide(description: "The task, starting with a verb. One sentence.")
    var task: String
    @Guide(description: "Person responsible, named exactly as the transcript names them. Empty if the transcript does not say.")
    var owner: String
    @Guide(description: "The due date phrase word for word as it was spoken. Empty if no date was spoken. Never work one out.")
    var dueText: String
    @Guide(description: "Timestamp mm:ss or h:mm:ss of the line where this was said.")
    var timestamp: String
}

@available(iOS 26, *)
@Generable(description: "Notes extracted from one part of a transcript.")
struct ChunkNotesGenerable {
    @Guide(description: "Key points discussed, each under 20 words.", .maximumCount(6))
    var keyPoints: [String]
    @Guide(description: "Decisions actually agreed on. Empty if none.", .maximumCount(6))
    var decisions: [String]
    @Guide(description: "Tasks someone agreed to do. Empty if none.", .maximumCount(8))
    var actionItems: [ActionItemDraftGenerable]
    @Guide(description: "Unresolved questions. Empty if none.", .maximumCount(5))
    var openQuestions: [String]
}

@available(iOS 26, *)
@Generable(description: "Key points on one subject the conversation covered.")
struct KeyPointTopicGenerable {
    @Guide(description: "The subject, 2–6 words, as the participants would name it.")
    var title: String
    @Guide(description: "Key points on this subject, each under 20 words. Statements, never questions. Never a point already used under another subject.", .maximumCount(5))
    var points: [String]
    @Guide(description: "Timestamp mm:ss or h:mm:ss of the first transcript line about this subject. Empty if unsure.")
    var startTimestamp: String?
}

@available(iOS 26, *)
@Generable(description: "Summary of a general meeting or lecture.")
struct GeneralSummaryGenerable {
    @Guide(description: "Short title, max 8 words.")
    var title: String
    @Guide(description: "A 5–8 sentence overview for someone who missed it: what the meeting was for, who took part as labeled, the main subjects in the order they came up, what was decided, and what was left open. Only what the transcript says.")
    var overview: String
    @Guide(description: "Key points grouped by subject, one topic per distinct subject in the order discussed. Never repeat a subject. A recording about one subject gets one topic.", .maximumCount(8))
    var topics: [KeyPointTopicGenerable]
    @Guide(description: "Decisions actually agreed on. Empty if none.", .maximumCount(8))
    var decisions: [String]
    @Guide(description: "Tasks someone agreed to do. Empty if none.", .maximumCount(10))
    var actionItems: [ActionItemDraftGenerable]
    @Guide(description: "Unresolved questions. Empty if none.", .maximumCount(6))
    var openQuestions: [String]
}

@available(iOS 26, *)
@Generable(description: "Summary of a meeting between a consultant and a client.")
struct ClientMeetingSummaryGenerable {
    @Guide(description: "Short title, max 8 words.")
    var title: String
    @Guide(description: "3–5 sentence overview.")
    var overview: String
    @Guide(description: "What the client wants to achieve, in their words where possible.", .maximumCount(6))
    var clientGoals: [String]
    @Guide(description: "Concerns, objections, budget or timeline constraints the client raised.", .maximumCount(6))
    var concerns: [String]
    @Guide(description: "Decisions actually agreed on. Empty if none.", .maximumCount(8))
    var decisions: [String]
    @Guide(description: "Tasks someone agreed to do. Empty if none.", .maximumCount(10))
    var actionItems: [ActionItemDraftGenerable]
    @Guide(description: "Next meeting or check-in if mentioned, else empty.")
    var nextMeeting: String
    @Guide(description: "Unresolved questions. Empty if none.", .maximumCount(6))
    var openQuestions: [String]
    @Guide(description: "The subjects discussed, in order, each with its key points and the time it came up. Never repeat a subject.", .maximumCount(8))
    var topics: [KeyPointTopicGenerable]
}

@available(iOS 26, *)
@Generable(description: "A follow-up email to the client.")
struct FollowUpEmailGenerable {
    var subject: String
    var body: String
}

@available(iOS 26, *)
@Generable(description: "A measurement spoken on site.")
struct MeasurementGenerable {
    @Guide(description: "What was measured, named as the transcript names it.")
    var item: String
    @Guide(description: "The value word for word as it was spoken. Never estimate, round or convert.")
    var value: String
}

@available(iOS 26, *)
@Generable(description: "A material mentioned for the job.")
struct MaterialGenerable {
    var name: String
    var quantity: String
    var notes: String
}

@available(iOS 26, *)
@Generable(description: "One room or area of the job.")
struct WorkAreaGenerable {
    @Guide(description: "The room or area, named as the transcript names it.")
    var name: String
    @Guide(description: "Work to be done in this area.", .maximumCount(10))
    var tasks: [String]
    @Guide(description: "Only measurements explicitly spoken. Never estimate or convert.", .maximumCount(12))
    var measurements: [MeasurementGenerable]
    @Guide(description: "Materials mentioned for this area. Empty if none.", .maximumCount(10))
    var materials: [MaterialGenerable]
    @Guide(description: "Timestamp mm:ss or h:mm:ss of the first transcript line in this area. Empty if unsure.")
    var startTimestamp: String?
}

@available(iOS 26, *)
@Generable(description: "Summary of a contractor walking a job site with a customer.")
struct WalkthroughSummaryGenerable {
    @Guide(description: "Short title, max 8 words.")
    var title: String
    @Guide(description: "Job address or location if spoken, else empty.")
    var location: String
    @Guide(description: "3–5 sentence overview.")
    var overview: String
    @Guide(description: "One entry per room or area walked, in the order visited. Never repeat an area.", .maximumCount(10))
    var areas: [WorkAreaGenerable]
    @Guide(description: "Specific customer requests or preferences (colors, brands, finishes).", .maximumCount(8))
    var customerRequests: [String]
    @Guide(description: "Problems found: damage, code, safety, access issues.", .maximumCount(8))
    var issuesFound: [String]
    @Guide(description: "Notes useful for writing the quote: scope, exclusions, permits, timeline.", .maximumCount(8))
    var quoteNotes: [String]
    @Guide(description: "Tasks someone agreed to do. Empty if none.", .maximumCount(10))
    var actionItems: [ActionItemDraftGenerable]
}

// MARK: - Compact drafts

// The same shapes with a third of the room, for a transcript too short to fill the full ones.
// Each converts straight to the payload type rather than to its full-sized twin, so nothing here
// has to construct a `@Generable` value.

@available(iOS 26, *)
@Generable(description: "One subject and the points made about it.")
struct KeyPointTopicCompactGenerable {
    @Guide(description: "The subject, 2–6 words, as the participants would name it.")
    var title: String
    @Guide(description: "Key points on this subject, each under 20 words. Statements, never questions.", .maximumCount(3))
    var points: [String]
    @Guide(description: "Timestamp mm:ss or h:mm:ss of the first transcript line about this subject. Empty if unsure.")
    var startTimestamp: String?
}

@available(iOS 26, *)
@Generable(description: "A short meeting summary.")
struct GeneralSummaryCompactGenerable {
    @Guide(description: "Short title, max 8 words.")
    var title: String
    @Guide(description: "A 2–4 sentence overview of what was said. Only what the transcript says.")
    var overview: String
    @Guide(description: "Key points grouped by subject. A recording about one subject gets one topic.", .maximumCount(2))
    var topics: [KeyPointTopicCompactGenerable]
    @Guide(description: "Decisions actually agreed on. Empty if none.", .maximumCount(3))
    var decisions: [String]
    @Guide(description: "Tasks someone agreed to do. Empty if none.", .maximumCount(4))
    var actionItems: [ActionItemDraftGenerable]
    @Guide(description: "Unresolved questions. Empty if none.", .maximumCount(3))
    var openQuestions: [String]
}

@available(iOS 26, *)
@Generable(description: "A short client meeting summary.")
struct ClientMeetingSummaryCompactGenerable {
    @Guide(description: "Short title, max 8 words.")
    var title: String
    @Guide(description: "A 2–4 sentence overview.")
    var overview: String
    @Guide(description: "What the client wants to achieve, in their words where possible.", .maximumCount(3))
    var clientGoals: [String]
    @Guide(description: "Concerns, objections, budget or timeline constraints the client raised.", .maximumCount(3))
    var concerns: [String]
    @Guide(description: "Decisions actually agreed on. Empty if none.", .maximumCount(3))
    var decisions: [String]
    @Guide(description: "Tasks someone agreed to do. Empty if none.", .maximumCount(4))
    var actionItems: [ActionItemDraftGenerable]
    @Guide(description: "Next meeting or check-in if mentioned, else empty.")
    var nextMeeting: String
    @Guide(description: "Unresolved questions. Empty if none.", .maximumCount(3))
    var openQuestions: [String]
    @Guide(description: "The subjects discussed, in order. Never repeat a subject.", .maximumCount(2))
    var topics: [KeyPointTopicCompactGenerable]
}

@available(iOS 26, *)
@Generable(description: "One room or area of a job site.")
struct WorkAreaCompactGenerable {
    @Guide(description: "The room or area, named as the transcript names it.")
    var name: String
    @Guide(description: "Work to be done in this area.", .maximumCount(3))
    var tasks: [String]
    @Guide(description: "Only measurements explicitly spoken. Never estimate or convert.", .maximumCount(4))
    var measurements: [MeasurementGenerable]
    @Guide(description: "Materials mentioned for this area. Empty if none.", .maximumCount(3))
    var materials: [MaterialGenerable]
    @Guide(description: "Timestamp mm:ss or h:mm:ss of the first transcript line in this area. Empty if unsure.")
    var startTimestamp: String?
}

@available(iOS 26, *)
@Generable(description: "A short job-site walk-through summary.")
struct WalkthroughSummaryCompactGenerable {
    @Guide(description: "Short title, max 8 words.")
    var title: String
    @Guide(description: "Job address or location if spoken, else empty.")
    var location: String
    @Guide(description: "A 2–4 sentence overview.")
    var overview: String
    @Guide(description: "One entry per room or area actually walked. Never repeat an area.", .maximumCount(2))
    var areas: [WorkAreaCompactGenerable]
    @Guide(description: "Specific customer requests or preferences.", .maximumCount(3))
    var customerRequests: [String]
    @Guide(description: "Problems found. Empty if none.", .maximumCount(3))
    var issuesFound: [String]
    @Guide(description: "Notes useful for writing the quote. Empty if none.", .maximumCount(3))
    var quoteNotes: [String]
    @Guide(description: "Tasks someone agreed to do. Empty if none.", .maximumCount(4))
    var actionItems: [ActionItemDraftGenerable]
}

// MARK: - How much room the answer gets

/// A short transcript handed the full schema is the padding engine.
///
/// The walkthrough schema offers ten areas, each with ten tasks, twelve measurements and ten
/// materials — over three hundred slots. On a 117-word recording the model filled them, and a
/// bound is also a budget: `.maximumCount` turned "runs until the window blows" into "runs until
/// the cap", which is an improvement in failure mode and none at all in content. So the cap is
/// chosen from the transcript rather than fixed.
///
/// This is deliberately not `DynamicGenerationSchema`, which is the obvious tool and stays on the
/// list (DECISIONS.md 2026-09-19). Building a schema at runtime means an API this project has not
/// verified against the SDK, and CLAUDE.md is explicit that these APIs are not to be written from
/// memory. Two statically-bounded tiers use `.maximumCount`, which is already in use and already
/// proven to be enforced by constrained decoding.
enum SummaryScale: Equatable, Sendable {
    case compact
    case full

    /// Below this, a transcript gets the compact schema. Roughly three minutes of speech: short
    /// enough that a full-sized answer would have to be invented, long enough that a real meeting
    /// isn't squeezed. A recording at the boundary loses nothing it had anything to say about.
    static let compactWordLimit = 400

    static func forTranscript(words: Int) -> SummaryScale {
        words < compactWordLimit ? .compact : .full
    }

    static func words(in text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }
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
@available(iOS 26, *)
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

    /// Compared by language code, never by `Locale.Language` equality (a regional variant must
    /// still match). Compiled against the iOS 26.5 SDK on 2026-09-19: `SystemLanguageModel.supportedLanguages: Set<Locale.Language>`.
    func supportsLanguage(_ language: Locale.Language) async -> Bool {
        guard let code = language.languageCode?.identifier else { return true }
        let supported = model.supportedLanguages
        guard !supported.isEmpty else { return true }
        return supported.contains { $0.languageCode?.identifier == code }
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
        let transcript = TranscriptChunker.text(for: input.lines)
        let counter = await tokenCounter(calibratedOn: transcript)
        // Asking for the compact schema is only a retry worth spending when the full one is what
        // the recording would otherwise get.
        let naturalScale = SummaryScale.forTranscript(words: SummaryScale.words(in: transcript))

        var finalInputTokens = budget.finalInputTokens
        var rateLimitWaits = 0
        var forceChunking = false
        var scaleOverride: SummaryScale?
        for attempt in 0...Self.maxOverflowRetries {
            do {
                return try await run(
                    input,
                    inputTokens: inputTokens,
                    finalInputTokens: finalInputTokens,
                    outputTokens: budget.outputReserve,
                    finalOutputTokens: budget.finalOutputReserve,
                    tokenCount: counter,
                    forceChunking: forceChunking,
                    scaleOverride: scaleOverride,
                    progress: progress
                )
            } catch is CancellationError {
                throw SummarizationError.cancelled
            } catch let error as SummarizationError {
                throw error
            } catch {
                // Both the iOS 26 `GenerationError` and the iOS 27 `LanguageModelError` land here.
                let kind = Self.kind(of: error)
                Self.log.notice("model call failed (\(String(describing: kind), privacy: .public)): \(String(describing: error), privacy: .private)")
                switch kind {
                case .rateLimited:
                    // The system throttles the model (often for minutes). Wait briefly twice, then
                    // hand back `.rateLimited` so the pipeline retries later instead of failing.
                    guard rateLimitWaits < Self.rateLimitDelays.count else { throw SummarizationError.rateLimited }
                    let delay = Self.rateLimitDelays[rateLimitWaits]
                    rateLimitWaits += 1
                    Self.log.notice("model rate limited; retrying in \(delay.description, privacy: .public)")
                    try await Task.sleep(for: delay)
                case .decodingFailure where scaleOverride == nil && naturalScale == .full:
                    // The answer wouldn't build into the type, which on device means it ran to its
                    // cap and stopped mid-array (2026-09-21). Shrinking the input is the wrong
                    // lever — the transcript wasn't what overflowed, the answer was — so ask for a
                    // smaller answer instead: the compact schema has a third of the topics and
                    // half the points. Chunking too, so a one-call attempt doesn't simply repeat.
                    guard attempt < Self.maxOverflowRetries else { throw Self.map(error, kind: kind) }
                    scaleOverride = .compact
                    forceChunking = true
                    Self.log.notice("answer didn't fit its schema; retrying with the compact schema")
                case .contextSizeExceeded, .decodingFailure:
                    // An overflow really is too much input, and a decoding failure that survived
                    // the compact schema is treated the same way. Only the chunk size shrinks
                    // (SPEC §11.2); the reserves stay. A transcript that already fits one call
                    // never reads the chunk size, so the retry would repeat the call that just
                    // failed: force the map-reduce path as well, which asks for short notes per
                    // chunk instead of a whole summary in one answer.
                    guard attempt < Self.maxOverflowRetries else {
                        throw kind == .decodingFailure ? Self.map(error, kind: kind) : SummarizationError.contextOverflow
                    }
                    inputTokens = ContextBudget.shrunk(inputTokens)
                    finalInputTokens = ContextBudget.shrunk(finalInputTokens)
                    forceChunking = true
                    Self.log.notice("answer ran on (\(String(describing: kind), privacy: .public)); retrying chunked at \(inputTokens, privacy: .public) tokens")
                case .timeout where attempt < Self.maxOverflowRetries:
                    // A request that ran out of time (seen on device after 110 s) gets smaller,
                    // faster calls before giving up for now.
                    inputTokens = ContextBudget.shrunk(inputTokens)
                    finalInputTokens = ContextBudget.shrunk(finalInputTokens)
                    forceChunking = true
                    Self.log.notice("model timed out; retrying chunked at \(inputTokens, privacy: .public) tokens")
                case .timeout:
                    throw SummarizationError.timedOut
                default:
                    throw Self.map(error, kind: kind)
                }
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
                options: Self.options(outputTokens: outputReserve)
            )
            return FollowUpEmail(subject: response.content.subject, body: response.content.body)
        } catch is CancellationError {
            throw SummarizationError.cancelled
        } catch let error as SummarizationError {
            throw error
        } catch {
            throw Self.map(error, kind: Self.kind(of: error))
        }
    }

    // MARK: Map-reduce

    /// The context budget subtracts an output reserve so the answer has room, but nothing made
    /// the model honour it: `maximumResponseTokens: nil` let one call keep generating until the
    /// prompt plus the output overran the window and the model threw `exceededContextWindowSize`.
    /// A short recording is the likeliest to hit that — with little to say the model pads the
    /// arrays — and shrinking the chunk size in response did nothing, because the transcript was
    /// never what filled the window. The reserve is the cap now, so a runaway answer stops at the
    /// budget instead of taking the whole summary down with it.
    private static func options(outputTokens: Int) -> GenerationOptions {
        GenerationOptions(sampling: nil, temperature: 0.25, maximumResponseTokens: outputTokens)
    }

    /// The reserve for the calls that don't build a whole context budget. `contextSize` reads 0
    /// while the system rate-limits metadata lookups, so fall back rather than cap at nothing.
    private var outputReserve: Int {
        let size = model.contextSize
        return ContextBudget.defaultOutputReserve(for: size < 1_024 ? Self.fallbackContextSize : size)
    }

    private func run(
        _ input: SummarizationInput,
        inputTokens: Int,
        finalInputTokens: Int,
        outputTokens: Int,
        finalOutputTokens: Int,
        tokenCount: @escaping (String) -> Int,
        forceChunking: Bool,
        scaleOverride: SummaryScale?,
        progress: @Sendable @escaping (SummarizationProgress) -> Void
    ) async throws -> SummaryPayload {
        let template = input.template
        let transcript = TranscriptChunker.text(for: input.lines)
        // Measured on the transcript, never on the notes the reduce step produces: a long meeting
        // reduced to a page of notes still has a long meeting's worth of things to say. A retry
        // after the answer overran its cap passes the smaller scale in instead.
        let scale = scaleOverride ?? SummaryScale.forTranscript(words: SummaryScale.words(in: transcript))
        // The whole transcript in one call is a FINAL call, so it's the FINAL call's input room
        // that decides whether it fits.
        if !forceChunking, TranscriptChunker.fitsInOneCall(input.lines, budgetTokens: finalInputTokens, tokenCount: tokenCount) {
            progress(SummarizationProgress(completedChunks: 0, totalChunks: 1))
            let payload = try await final(from: transcript, template: template, fromTranscript: true, focus: input.focus, outputTokens: finalOutputTokens, scale: scale)
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
            let result = try await mapChunk(chunk.text, outputTokens: outputTokens)
            notes.append(Self.render(result))
            completed += 1
            progress(SummarizationProgress(completedChunks: completed, totalChunks: total))
        }

        // REDUCE: while the notes don't fit one call, combine them in groups (SPEC §11.3).
        var combined = notes.joined(separator: "\n\n")
        while tokenCount(combined) > finalInputTokens, notes.count > 1 {
            try Task.checkCancellation()
            let groups = Self.group(notes, budgetTokens: inputTokens, tokenCount: tokenCount)
            total += groups.count
            progress(SummarizationProgress(completedChunks: completed, totalChunks: total))
            var reduced: [String] = []
            for group in groups {
                try Task.checkCancellation()
                let result = try await mapChunk(group.joined(separator: "\n\n"), outputTokens: outputTokens)
                reduced.append(Self.render(result))
                completed += 1
                progress(SummarizationProgress(completedChunks: completed, totalChunks: total))
            }
            guard reduced.count < notes.count else { break } // no progress possible; let the final call decide
            notes = reduced
            combined = notes.joined(separator: "\n\n")
        }

        let payload = try await final(from: combined, template: template, fromTranscript: false, focus: input.focus, outputTokens: finalOutputTokens, scale: scale)
        completed += 1
        progress(SummarizationProgress(completedChunks: completed, totalChunks: total))
        return payload
    }

    private func mapChunk(_ text: String, outputTokens: Int) async throws -> ChunkNotesGenerable {
        let session = LanguageModelSession(instructions: Prompts.instructions(Prompts.map))
        return try await session.respond(
            to: Prompt { text },
            generating: ChunkNotesGenerable.self,
            options: Self.options(outputTokens: outputTokens)
        ).content
    }

    /// The focus line adds at most ~60 tokens to the instructions; the output reserve absorbs it,
    /// so the per-template budget cache stays valid.
    private func final(from text: String, template: TemplateID, fromTranscript: Bool, focus: String, outputTokens: Int, scale: SummaryScale) async throws -> SummaryPayload {
        let step = fromTranscript ? Prompts.finalFromTranscript(for: template) : Prompts.final(for: template)
        let session = LanguageModelSession(instructions: Prompts.instructions(step, focus: focus))
        let prompt = Prompt { text }
        let options = Self.options(outputTokens: outputTokens)
        Self.log.info("final call: \(String(describing: template), privacy: .public) schema, \(String(describing: scale), privacy: .public)")
        switch (template, scale) {
        case (.general, .full):
            let content = try await session.respond(to: prompt, generating: GeneralSummaryGenerable.self, options: options).content
            return .general(Self.summary(content))
        case (.general, .compact):
            let content = try await session.respond(to: prompt, generating: GeneralSummaryCompactGenerable.self, options: options).content
            return .general(Self.summary(content))
        case (.client, .full):
            let content = try await session.respond(to: prompt, generating: ClientMeetingSummaryGenerable.self, options: options).content
            return .client(Self.summary(content))
        case (.client, .compact):
            let content = try await session.respond(to: prompt, generating: ClientMeetingSummaryCompactGenerable.self, options: options).content
            return .client(Self.summary(content))
        case (.walkthrough, .full):
            let content = try await session.respond(to: prompt, generating: WalkthroughSummaryGenerable.self, options: options).content
            return .walkthrough(Self.summary(content))
        case (.walkthrough, .compact):
            let content = try await session.respond(to: prompt, generating: WalkthroughSummaryCompactGenerable.self, options: options).content
            return .walkthrough(Self.summary(content))
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
        if #available(iOS 26.4, macOS 26.4, *) {
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
        Self.log.info("""
            context \(contextSize, privacy: .public) tokens; instructions \(instructionTokens, privacy: .public); \
            schema \(schemaTokens, privacy: .public); chunk budget \(budget.inputTokens, privacy: .public) \
            (answer \(budget.outputReserve, privacy: .public)); final budget \(budget.finalInputTokens, privacy: .public) \
            (answer \(budget.finalOutputReserve, privacy: .public))
            """)
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
        if #available(iOS 26.4, macOS 26.4, *), !sample.isEmpty, model.contextSize >= 1_024, let counted = try? await model.tokenCount(for: Prompt { sample }) {
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

    static func topic(_ draft: KeyPointTopicGenerable) -> KeyPointTopic {
        KeyPointTopic(title: draft.title, points: draft.points, start: ActionItemPostProcessor.parseTimestamp(draft.startTimestamp ?? ""))
    }

    static func topic(_ draft: KeyPointTopicCompactGenerable) -> KeyPointTopic {
        KeyPointTopic(title: draft.title, points: draft.points, start: ActionItemPostProcessor.parseTimestamp(draft.startTimestamp ?? ""))
    }

    // Each tier maps itself. The two shapes are identical field for field — only the counts in
    // their guides differ — so the payload types below are built twice rather than converting a
    // compact draft into a full one, which would mean constructing a `@Generable` value.

    static func summary(_ draft: GeneralSummaryGenerable) -> GeneralSummary {
        GeneralSummary(
            title: draft.title,
            overview: draft.overview,
            keyPoints: draft.topics.flatMap(\.points),
            topics: draft.topics.map(Self.topic),
            decisions: draft.decisions,
            actionItems: draft.actionItems.map(Self.actionItem),
            openQuestions: draft.openQuestions
        )
    }

    static func summary(_ draft: GeneralSummaryCompactGenerable) -> GeneralSummary {
        GeneralSummary(
            title: draft.title,
            overview: draft.overview,
            keyPoints: draft.topics.flatMap(\.points),
            topics: draft.topics.map(Self.topic),
            decisions: draft.decisions,
            actionItems: draft.actionItems.map(Self.actionItem),
            openQuestions: draft.openQuestions
        )
    }

    static func summary(_ draft: ClientMeetingSummaryGenerable) -> ClientMeetingSummary {
        ClientMeetingSummary(
            title: draft.title,
            overview: draft.overview,
            clientGoals: draft.clientGoals,
            concerns: draft.concerns,
            decisions: draft.decisions,
            actionItems: draft.actionItems.map(Self.actionItem),
            nextMeeting: draft.nextMeeting,
            openQuestions: draft.openQuestions,
            topics: draft.topics.map(Self.topic)
        )
    }

    static func summary(_ draft: ClientMeetingSummaryCompactGenerable) -> ClientMeetingSummary {
        ClientMeetingSummary(
            title: draft.title,
            overview: draft.overview,
            clientGoals: draft.clientGoals,
            concerns: draft.concerns,
            decisions: draft.decisions,
            actionItems: draft.actionItems.map(Self.actionItem),
            nextMeeting: draft.nextMeeting,
            openQuestions: draft.openQuestions,
            topics: draft.topics.map(Self.topic)
        )
    }

    static func summary(_ draft: WalkthroughSummaryGenerable) -> WalkthroughSummary {
        WalkthroughSummary(
            title: draft.title,
            location: draft.location,
            overview: draft.overview,
            areas: draft.areas.map { area in
                WorkArea(
                    name: area.name,
                    tasks: area.tasks,
                    measurements: area.measurements.map { Measurement(item: $0.item, value: $0.value, timestamp: nil) },
                    materials: area.materials.map { Material(name: $0.name, quantity: $0.quantity, notes: $0.notes) },
                    start: ActionItemPostProcessor.parseTimestamp(area.startTimestamp ?? "")
                )
            },
            customerRequests: draft.customerRequests,
            issuesFound: draft.issuesFound,
            quoteNotes: draft.quoteNotes,
            actionItems: draft.actionItems.map(Self.actionItem)
        )
    }

    static func summary(_ draft: WalkthroughSummaryCompactGenerable) -> WalkthroughSummary {
        WalkthroughSummary(
            title: draft.title,
            location: draft.location,
            overview: draft.overview,
            areas: draft.areas.map { area in
                WorkArea(
                    name: area.name,
                    tasks: area.tasks,
                    measurements: area.measurements.map { Measurement(item: $0.item, value: $0.value, timestamp: nil) },
                    materials: area.materials.map { Material(name: $0.name, quantity: $0.quantity, notes: $0.notes) },
                    start: ActionItemPostProcessor.parseTimestamp(area.startTimestamp ?? "")
                )
            },
            customerRequests: draft.customerRequests,
            issuesFound: draft.issuesFound,
            quoteNotes: draft.quoteNotes,
            actionItems: draft.actionItems.map(Self.actionItem)
        )
    }

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

    /// What went wrong, whichever error type the OS threw: the iOS 26 `GenerationError` this SDK
    /// knows, or the iOS 27 `LanguageModelError` recognised by name (`LanguageModelErrorBridge`).
    static func kind(of error: any Error) -> LanguageModelErrorBridge.Kind {
        if let error = error as? LanguageModelSession.GenerationError {
            switch error {
            case .exceededContextWindowSize: return .contextSizeExceeded
            case .decodingFailure: return .decodingFailure
            case .rateLimited: return .rateLimited
            case .refusal: return .refusal
            case .guardrailViolation: return .guardrailViolation
            case .unsupportedLanguageOrLocale: return .unsupportedLanguageOrLocale
            default: return .unknown
            }
        }
        return LanguageModelErrorBridge.kind(of: error) ?? .unknown
    }

    static func map(_ error: any Error, kind: LanguageModelErrorBridge.Kind) -> SummarizationError {
        if let error = error as? LanguageModelSession.GenerationError {
            switch error {
            case .assetsUnavailable:
                return .unavailable(.modelNotReady)
            case .decodingFailure:
                return .generationFailed(SummarizationError.answerCutOffMessage)
            default:
                break
            }
        }
        switch kind {
        case .contextSizeExceeded:
            return .contextOverflow
        case .decodingFailure:
            return .generationFailed(SummarizationError.answerCutOffMessage)
        case .rateLimited:
            return .rateLimited
        case .timeout:
            return .timedOut
        case .guardrailViolation:
            return .generationFailed("The on-device model declined this content (safety guardrails).")
        case .refusal:
            return .generationFailed("The on-device model declined to summarize this recording.")
        case .unsupportedLanguageOrLocale:
            return .generationFailed("The on-device model doesn't support this language yet.")
        case .unsupported:
            return .generationFailed("The on-device model couldn't process this request.")
        case .unknown:
            return .generationFailed(error.localizedDescription)
        }
    }
}
