import Foundation
import SwiftUI

/// Every injectable service, bundled so views and view models get them from the environment (SPEC §6.2).
struct AppServices: Sendable {
    var recorder: any AudioRecorderService
    var importer: any AudioImportService
    var transcription: any TranscriptionService
    var diarization: any DiarizationService
    var aligner: any TranscriptAligning
    var summarization: any SummarizationService
    var dueDates: any DueDateResolving
    var exporter: any ExportService
    var pipeline: any PipelineCoordinating
    var capabilities: any CapabilityService
    var purchases: any PurchaseService
    var storage: RecordingStorage

    /// All fakes. Used by tests, previews, and (until each milestone lands its real service) the app itself.
    static func fakes(storage: RecordingStorage? = nil) -> AppServices {
        AppServices(
            recorder: FakeAudioRecorderService(),
            importer: FakeAudioImportService(),
            transcription: FakeTranscriptionService(),
            diarization: FakeDiarizationService(),
            aligner: FakeTranscriptAligner(),
            summarization: FakeSummarizationService(),
            dueDates: FakeDueDateResolver(),
            exporter: FakeExportService(),
            pipeline: FakePipelineCoordinator(),
            capabilities: FakeCapabilityService(),
            purchases: FakePurchaseService(),
            storage: storage ?? RecordingStorage(rootDirectory: FileManager.default.temporaryDirectory.appending(path: "Recordings"))
        )
    }

    /// The services the shipping app uses. Real implementations replace fakes milestone by milestone:
    /// M1 recorder, M2 importer, M3 transcription + pipeline, M4 diarization + aligner,
    /// M5 summarization + due dates, M6 exporter, M7 capabilities, M8 purchases.
    static func live() throws -> AppServices {
        let storage = try RecordingStorage.appDefault()
        var services = fakes(storage: storage)
        services.recorder = LiveAudioRecorderService(capacityProvider: { storage.availableCapacity() })
        services.importer = LiveAudioImportService()
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
