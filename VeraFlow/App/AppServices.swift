import Foundation
import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

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
    /// v1.1: local "Summary ready" notifications (plan item 6).
    var notifications: any NotificationService
    /// v1.1: "Ask this recording" (plan item 11).
    var questions: any QuestionService
    /// v1.1: which languages a recording can be translated into (plan item 14).
    var translation: any TranslationService
    /// v1.1: words while recording (plan item 4).
    var transcriptPreview: any TranscriptPreviewService
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
            notifications: FakeNotificationService(),
            questions: FakeQuestionService(),
            translation: FakeTranslationService(),
            transcriptPreview: FakeTranscriptPreviewService(),
            storage: storage ?? RecordingStorage(rootDirectory: FileManager.default.temporaryDirectory.appending(path: "Recordings")),
            benchmarkEngines: [.init(name: "Sample", service: transcription)]
        )
    }

    /// The services the shipping app uses. Real implementations replace fakes milestone by milestone:
    /// M1 recorder, M2 importer, M3 transcription + pipeline, M4 diarization + aligner (done),
    /// M5 summarization + due dates (done), M6 exporter (done), M7 capabilities (done), M8 purchases (done).
    static func live(container: ModelContainer) throws -> AppServices {
        let storage = try RecordingStorage.appDefault()
        var services = fakes(storage: storage)
        services.recorder = LiveAudioRecorderService(capacityProvider: { storage.availableCapacity() })
        #if os(iOS)
        services.activity = LiveRecordingActivityService()
        #else
        services.activity = NoRecordingActivityService()   // no Live Activities on the Mac (plan item 15)
        #endif
        services.importer = LiveAudioImportService()
        // iOS 26: Apple's engine, with Parakeet behind the debug benchmark screen (SPEC §9.4).
        // iOS 18–25: Parakeet is the engine, and there is no on-device model for summaries, Ask,
        // or live words (v1.1 plan item 16). Release builds have one model-download path per OS.
        let parakeet = ParakeetTranscriptionService()
        if #available(iOS 26, *) {
            let apple = LiveTranscriptionService()
            #if DEBUG
            services.transcription = EngineSelectingTranscriptionService(apple: apple, parakeet: parakeet)
            services.benchmarkEngines = [.init(name: "Apple Speech", service: apple), .init(name: "Parakeet", service: parakeet)]
            #else
            services.transcription = apple
            services.benchmarkEngines = []
            #endif
        } else {
            services.transcription = parakeet
            services.benchmarkEngines = []
        }
        services.diarization = LiveDiarizationService()
        services.aligner = LiveTranscriptAligner()
        services.dueDates = LiveDueDateResolver()
        services.exporter = LiveExportService()
        services.purchases = LivePurchaseService()
        services.notifications = LiveNotificationService()
        services.translation = LiveTranslationService()
        if #available(iOS 26, *) {
            services.summarization = LiveSummarizationService()
            services.questions = LiveQuestionService()
            services.transcriptPreview = LiveTranscriptPreview()
            services.capabilities = LiveCapabilityService(
                transcription: services.transcription,
                diarization: services.diarization,
                summarization: services.summarization
            )
            #if os(iOS)
            services.background = LiveBackgroundProcessing()
            #else
            services.background = InlineBackgroundProcessing()   // the Mac keeps running; nothing to hand off
            #endif
        } else {
            services.summarization = UnavailableSummarizationService()
            services.questions = UnavailableQuestionService()
            services.transcriptPreview = UnavailableTranscriptPreview()
            services.capabilities = LegacyCapabilityService(transcription: services.transcription, diarization: services.diarization)
            services.background = InlineBackgroundProcessing()
        }
        services.pipeline = LivePipelineCoordinator(
            container: container,
            transcription: services.transcription,
            diarization: services.diarization,
            aligner: services.aligner,
            summarization: services.summarization,
            dueDates: services.dueDates,
            purchases: services.purchases,
            storage: storage,
            background: services.background,
            speakerHint: { SpeakerCountHint(DiarizationPreference.expectedSpeakers()) },
            isAppActive: { await Self.isAppActive() }
        )
        return services
    }
}

extension AppServices {
    /// Whether the pipeline may start foreground-only stages. iOS suspends a backgrounded app;
    /// a Mac app keeps running whether or not its window is in front.
    @MainActor
    static func isAppActive() -> Bool {
        #if os(iOS)
        UIApplication.shared.applicationState != .background
        #else
        true
        #endif
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
