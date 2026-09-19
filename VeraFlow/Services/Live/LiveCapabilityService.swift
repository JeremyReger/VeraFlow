import BackgroundTasks
import Foundation
import FoundationModels
import Speech

/// Probes what this iPhone can do (SPEC §15) by asking the real services plus the two system
/// checks that don't belong to any service: which speech engine exists and the OS version.
@available(iOS 26, *)
actor LiveCapabilityService: CapabilityService {
    private let transcription: any TranscriptionService
    private let diarization: any DiarizationService
    private let summarization: any SummarizationService

    init(
        transcription: any TranscriptionService,
        diarization: any DiarizationService,
        summarization: any SummarizationService
    ) {
        self.transcription = transcription
        self.diarization = diarization
        self.summarization = summarization
    }

    func refresh() async -> Capabilities {
        let engine: TranscriptionEngine?
        if SpeechTranscriber.isAvailable {
            engine = .speechTranscriber
        } else if await !DictationTranscriber.supportedLocales.isEmpty {
            engine = .dictationTranscriber
        } else {
            engine = nil
        }
        // The chosen transcription language, else the device's (v1.1 plan item 8).
        let locale = AppPreferences.effectiveTranscriptionLocale()
        let assets = engine == nil ? TranscriptionAssetStatus.localeUnsupported : await transcription.assetStatus(for: locale)
        let hasRuntimeContextSize: Bool
        if #available(iOS 26.4, *) {
            hasRuntimeContextSize = true
        } else {
            hasRuntimeContextSize = false
        }
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return Capabilities(
            transcriptionEngine: engine,
            transcriptionAssets: assets,
            diarizationModelsReady: await diarization.modelsReady(),
            summarization: await summarization.availability(),
            hasRuntimeContextSize: hasRuntimeContextSize,
            backgroundProcessingSupported: Self.backgroundProcessingSupported,
            osVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        )
    }

    /// Continued-processing tasks exist on iOS 26 devices; the Simulator reports them unavailable.
    nonisolated static var backgroundProcessingSupported: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }
}
