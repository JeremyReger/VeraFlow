import Foundation

/// Which implementations the shipping app uses on this iOS (v1.1 plan item 16). Apple's
/// `SpeechAnalyzer` and the on-device Foundation Models arrive with iOS 26; older iPhones
/// transcribe with FluidAudio's Parakeet and get speaker labels, but no AI summaries, Ask, or
/// live words while recording. The pure decision is here so tests can cover both branches.
enum PlatformPolicy {
    enum SpeechEngine: Equatable, Sendable {
        case appleSpeech
        case parakeet
    }

    static let firstAppleSpeechMajor = 26

    static func speechEngine(osMajorVersion: Int) -> SpeechEngine {
        osMajorVersion >= firstAppleSpeechMajor ? .appleSpeech : .parakeet
    }

    /// Foundation Models need iOS 26 as well as an eligible iPhone.
    static func summariesPossible(osMajorVersion: Int) -> Bool {
        osMajorVersion >= firstAppleSpeechMajor
    }

    static var currentMajorVersion: Int {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    }
}

/// Capabilities on iOS 18–25: Parakeet transcribes, the diarizer labels, nothing summarizes.
actor LegacyCapabilityService: CapabilityService {
    private let transcription: any TranscriptionService
    private let diarization: any DiarizationService
    private let osVersion: String

    init(transcription: any TranscriptionService, diarization: any DiarizationService, osVersion: String? = nil) {
        self.transcription = transcription
        self.diarization = diarization
        let version = ProcessInfo.processInfo.operatingSystemVersion
        self.osVersion = osVersion ?? "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    func refresh() async -> Capabilities {
        let locale = AppPreferences.effectiveTranscriptionLocale()
        let available = await transcription.isAvailable()
        return Capabilities(
            transcriptionEngine: available ? .parakeet : nil,
            transcriptionAssets: available ? await transcription.assetStatus(for: locale) : .localeUnsupported,
            diarizationModelsReady: await diarization.modelsReady(),
            summarization: .deviceNotEligible,
            hasRuntimeContextSize: false,
            backgroundProcessingSupported: false,
            osVersion: osVersion
        )
    }
}

/// Summaries on an iOS that has no on-device model: every call reports the reason.
struct UnavailableSummarizationService: SummarizationService {
    var reason: SummarizationAvailability = .deviceNotEligible

    func availability() async -> SummarizationAvailability { reason }
    func supportsLanguage(_ language: Locale.Language) async -> Bool { false }
    func prewarm() async {}

    func summarize(_ input: SummarizationInput, progress: @Sendable @escaping (SummarizationProgress) -> Void) async throws -> SummaryPayload {
        throw SummarizationError.unavailable(reason)
    }

    func followUpEmail(for summary: ClientMeetingSummary) async throws -> FollowUpEmail {
        throw SummarizationError.unavailable(reason)
    }

    func modelInfo() async -> String { "No on-device model on this iOS" }
}

/// "Ask this recording" without a model: the tab shows the same reason as the Summary tab.
struct UnavailableQuestionService: QuestionService {
    var reason: SummarizationAvailability = .deviceNotEligible

    func availability() async -> SummarizationAvailability { reason }
    func excerptBudgetTokens() async -> Int { 0 }

    func answer(question: String, excerpts: [TranscriptLine]) async throws -> RawAnswer {
        throw SummarizationError.unavailable(reason)
    }
}

/// Runs pipeline work inline. Continued-processing tasks are iOS 26; on older iPhones the
/// pipeline already keeps its own foreground catch-up (DECISIONS 2026-09-18).
struct InlineBackgroundProcessing: BackgroundProcessing {
    func run(title: String, work: @Sendable @escaping (_ progress: @Sendable @escaping (Double) -> Void) async -> Void) async {
        await work { _ in }
    }
}

/// No live words without `SpeechTranscriber`; the Record screen just shows no block.
struct UnavailableTranscriptPreview: TranscriptPreviewService {
    func isAvailable(locale: Locale) async -> Bool { false }
    func start(locale: Locale) async throws -> PreviewSession { throw TranscriptPreviewError.unavailable }
    func stop() async {}
}
