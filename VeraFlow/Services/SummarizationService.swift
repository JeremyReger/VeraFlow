import Foundation

/// One transcript line handed to the model: `[mm:ss] Speaker N: text` (SPEC §11.3).
struct TranscriptLine: Sendable, Equatable {
    var start: TimeInterval
    var speakerKey: String?
    var speakerDisplayName: String
    var text: String
}

/// Everything the summarizer needs about a recording.
struct SummarizationInput: Sendable, Equatable {
    var recordingTitle: String
    var recordedAt: Date
    var duration: TimeInterval
    var lines: [TranscriptLine]
    var template: TemplateID
}

/// Why on-device summaries aren't available right now (SPEC §11.1).
enum SummarizationAvailability: Sendable, Equatable {
    case available
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unknown(String)

    var isAvailable: Bool { self == .available }
}

enum SummarizationError: Error, Equatable {
    case unavailable(SummarizationAvailability)
    /// The free tier's 3 summaries are used up (SPEC §13.2); the Summary tab offers the unlock.
    case freeLimitReached
    /// The system throttled the on-device model; the pipeline retries on its own later.
    case rateLimited
    /// The model didn't answer in time even with smaller chunks; retried later like a rate limit.
    case timedOut
    case contextOverflow
    case generationFailed(String)
    case cancelled

    static let freeLimitMessage = "You've used your \(FreeTier.summaryLimit) free summaries. Unlock VeraFlow for unlimited summaries."
    static let rateLimitedMessage = "The on-device model is busy right now. VeraFlow will try again in a few minutes."
    static let timedOutMessage = "The on-device model took too long to answer. VeraFlow will try again in a few minutes."
}

/// Progress of a map-reduce summary run.
struct SummarizationProgress: Sendable, Equatable {
    var completedChunks: Int
    var totalChunks: Int

    var fraction: Double {
        totalChunks == 0 ? 0 : Double(completedChunks) / Double(totalChunks)
    }
}

/// Generates template summaries with the on-device model (SPEC §11). Implemented for real in M5.
protocol SummarizationService: Sendable {
    func availability() async -> SummarizationAvailability
    /// Loads the model ahead of time so the first summary starts faster.
    func prewarm() async
    func summarize(
        _ input: SummarizationInput,
        progress: @Sendable @escaping (SummarizationProgress) -> Void
    ) async throws -> SummaryPayload
    /// Drafts a follow-up email from a client-meeting summary (SPEC §11.4).
    func followUpEmail(for summary: ClientMeetingSummary) async throws -> FollowUpEmail
    /// Describes the model for `SummaryRecord.modelInfo`.
    func modelInfo() async -> String
}

/// Returns a canned summary built from the input's lines.
actor FakeSummarizationService: SummarizationService {
    var availabilityToReport: SummarizationAvailability = .available
    var errorToThrow: SummarizationError?
    private(set) var prewarmCount = 0
    private(set) var inputs: [SummarizationInput] = []

    init(availability: SummarizationAvailability = .available) {
        self.availabilityToReport = availability
    }

    func availability() async -> SummarizationAvailability { availabilityToReport }

    func prewarm() async { prewarmCount += 1 }

    func summarize(
        _ input: SummarizationInput,
        progress: @Sendable @escaping (SummarizationProgress) -> Void
    ) async throws -> SummaryPayload {
        if let errorToThrow { throw errorToThrow }
        guard availabilityToReport.isAvailable else {
            throw SummarizationError.unavailable(availabilityToReport)
        }
        inputs.append(input)
        progress(SummarizationProgress(completedChunks: 1, totalChunks: 1))

        let keyPoints = input.lines.prefix(3).map(\.text)
        let firstLine = input.lines.first
        let actionItem = ActionItem(
            task: "Follow up on: \(firstLine?.text ?? "the discussion")",
            owner: firstLine?.speakerDisplayName ?? "",
            ownerSpeakerKey: firstLine?.speakerKey,
            dueText: "",
            timestamp: firstLine?.start
        )
        let overview = "Fake summary of \(input.lines.count) transcript lines."

        switch input.template {
        case .general:
            return .general(GeneralSummary(
                title: input.recordingTitle,
                overview: overview,
                keyPoints: keyPoints,
                decisions: [],
                actionItems: [actionItem],
                openQuestions: []
            ))
        case .client:
            return .client(ClientMeetingSummary(
                title: input.recordingTitle,
                overview: overview,
                clientGoals: keyPoints,
                concerns: [],
                decisions: [],
                actionItems: [actionItem],
                nextMeeting: "",
                openQuestions: []
            ))
        case .walkthrough:
            return .walkthrough(WalkthroughSummary(
                title: input.recordingTitle,
                location: "",
                overview: overview,
                areas: [WorkArea(name: "Site", tasks: keyPoints, measurements: [], materials: [])],
                customerRequests: [],
                issuesFound: [],
                quoteNotes: [],
                actionItems: [actionItem]
            ))
        }
    }

    func followUpEmail(for summary: ClientMeetingSummary) async throws -> FollowUpEmail {
        if let errorToThrow { throw errorToThrow }
        return FollowUpEmail(
            subject: "Follow-up: \(summary.title)",
            body: summary.overview
        )
    }

    func modelInfo() async -> String { "FakeSummarizationService" }

    // MARK: Test controls

    func setAvailability(_ availability: SummarizationAvailability) { availabilityToReport = availability }
    func setError(_ error: SummarizationError?) { errorToThrow = error }
}
