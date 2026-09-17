import Foundation

/// Everything the UI needs to know about what this device can do (SPEC §15).
struct Capabilities: Sendable, Equatable {
    /// `SpeechTranscriber` available (full quality) vs. `DictationTranscriber` fallback.
    var transcriptionEngine: TranscriptionEngine?
    var transcriptionAssets: TranscriptionAssetStatus
    var diarizationModelsReady: Bool
    var summarization: SummarizationAvailability
    /// iOS 27+: context size and token counts can be read at runtime (SPEC §11.2).
    var hasRuntimeContextSize: Bool
    var backgroundProcessingSupported: Bool
    var osVersion: String

    var canTranscribe: Bool { transcriptionEngine != nil }
    var canSummarize: Bool { summarization.isAvailable }

    /// Everything on for previews and tests.
    static let allAvailable = Capabilities(
        transcriptionEngine: .speechTranscriber,
        transcriptionAssets: .ready,
        diarizationModelsReady: true,
        summarization: .available,
        hasRuntimeContextSize: true,
        backgroundProcessingSupported: true,
        osVersion: "27.0"
    )

    /// An iOS 26 iPhone without Apple Intelligence (SPEC §4.1 messaging).
    static let noAppleIntelligence = Capabilities(
        transcriptionEngine: .dictationTranscriber,
        transcriptionAssets: .ready,
        diarizationModelsReady: true,
        summarization: .deviceNotEligible,
        hasRuntimeContextSize: false,
        backgroundProcessingSupported: true,
        osVersion: "26.0"
    )
}

/// Probes the device's capabilities (SPEC §15). Implemented for real in M7; earlier milestones fill in fields as they land.
protocol CapabilityService: Sendable {
    /// Re-runs every check and returns the current state.
    func refresh() async -> Capabilities
}

actor FakeCapabilityService: CapabilityService {
    var capabilities: Capabilities
    private(set) var refreshCount = 0

    init(capabilities: Capabilities = .allAvailable) {
        self.capabilities = capabilities
    }

    func refresh() async -> Capabilities {
        refreshCount += 1
        return capabilities
    }

    func set(_ capabilities: Capabilities) {
        self.capabilities = capabilities
    }
}
