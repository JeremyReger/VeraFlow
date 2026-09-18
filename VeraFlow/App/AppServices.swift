import Foundation
import SwiftData
import SwiftUI

/// Every injectable service, bundled so views and view models get them from the environment (SPEC §6.2).
struct AppServices: Sendable {
    var recorder: any AudioRecorderService
    var activity: any RecordingActivityService
    var importer: any AudioImportService
    var transcription: any TranscriptionService
    var diarization: any DiarizationService
    var aligner: any TranscriptAligning
    var summarization: any SummarizationService
    var dueDates: any DueDateResolving
    var exporter: any ExportService
    var pipeline: any PipelineCoordinating
    var background: any BackgroundProcessing
    var capabilities: any CapabilityService
    var purchases: any PurchaseService
    var storage: RecordingStorage
    /// Every speech engine the debug benchmark can compare (SPEC §9.4). Release builds still
    /// carry the list; only the screen that uses it is DEBUG-only.
    var benchmarkEngines: [TranscriptionBenchmark.Engine]

    /// All fakes. Used by tests, previews, and (until each milestone lands its real service) the app itself.
    static func fakes(storage: RecordingStorage? = nil) -> AppServices {
        let transcription = FakeTranscriptionService()
        return AppServices(
            recorder: FakeAudioRecorderService(),
            activity: FakeRecordingActivityService(),
            importer: FakeAudioImportService(),
            transcription: transcription,
            diarization: FakeDiarizationService(),
            aligner: FakeTranscriptAligner(),
            summarization: FakeSummarizationService(),
            dueDates: FakeDueDateResolver(),
            exporter: FakeExportService(),
            pipeline: FakePipelineCoordinator(),
            background: FakeBackgroundProcessing(),
            capabilities: FakeCapabilityService(),
            purchases: FakePurchaseService(),
            storage: storage ?? RecordingStorage(rootDirectory: FileManager.default.temporaryDirectory.appending(path: "Recordings")),
            benchmarkEngines: [.init(name: "Sample", service: transcription)]
        )
    }

    /// The services the shipping app uses. Real implementations replace fakes milestone by milestone:
    /// M1 recorder, M2 importer, M3 transcription + pipeline, M4 diarization + aligner (done),
    /// M5 summarization + due dates, M6 exporter, M7 capabilities, M8 purchases.
    static func live(container: ModelContainer) throws -> AppServices {
        let storage = try RecordingStorage.appDefault()
        var services = fakes(storage: storage)
        services.recorder = LiveAudioRecorderService(capacityProvider: { storage.availableCapacity() })
        services.activity = LiveRecordingActivityService()
        services.importer = LiveAudioImportService()
        // Apple's engine by default; the debug benchmark screen can switch to Parakeet (SPEC §9.4).
        let apple = LiveTranscriptionService()
        let parakeet = ParakeetTranscriptionService()
        services.transcription = EngineSelectingTranscriptionService(apple: apple, parakeet: parakeet)
        services.benchmarkEngines = [.init(name: "Apple Speech", service: apple), .init(name: "Parakeet", service: parakeet)]
        services.diarization = LiveDiarizationService()
        services.aligner = LiveTranscriptAligner()
        services.dueDates = LiveDueDateResolver()
        // `summarization` stays the fake until the Foundation Models service lands (M5 half B,
        // docs/plans/2026-09-17-m5-summaries.md); the fake reports itself as available.
        services.background = LiveBackgroundProcessing()
        services.pipeline = LivePipelineCoordinator(
            container: container,
            transcription: services.transcription,
            diarization: services.diarization,
            aligner: services.aligner,
            summarization: services.summarization,
            dueDates: services.dueDates,
            storage: storage,
            background: services.background,
            speakerHint: { SpeakerCountHint(DiarizationPreference.expectedSpeakers()) }
        )
        return services
    }
}

private struct AppServicesKey: EnvironmentKey {
    static let defaultValue: AppServices = .fakes()
}

extension EnvironmentValues {
    var services: AppServices {
        get { self[AppServicesKey.self] }
        set { self[AppServicesKey.self] = newValue }
    }
}
