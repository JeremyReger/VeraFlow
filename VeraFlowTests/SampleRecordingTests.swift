import Foundation
import SwiftData
import Testing
@testable import VeraFlow

/// The bundled sample (v1.1 plan item 7) is an archive imported with the sample source.
@MainActor
struct SampleRecordingTests {
    @Test("Installing the sample adds one tagged recording with its summary, spends no free summary, and doesn't duplicate")
    func install() async throws {
        let scratch = try TestAudioFiles.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let storage = RecordingStorage(rootDirectory: scratch.appending(path: "Recordings", directoryHint: .isDirectory))
        var services = AppServices.fakes(storage: storage)
        let purchases = FakePurchaseService(unlocked: false, freeSummariesUsed: 1)
        let pipeline = FakePipelineCoordinator()
        services.purchases = purchases
        services.pipeline = pipeline
        let container = try ModelContainerFactory.makeInMemory()
        let actions = LibraryActions(context: container.mainContext, services: services)

        // A package as Jeremy would produce it: one finished recording with audio.
        let sample = PreviewData.sampleRecording()
        let audio = scratch.appending(path: "audio.aac")
        try TestAudioFiles.writeToneAAC(to: audio, seconds: 1)
        let package = scratch.appending(path: SampleRecording.folderName, directoryHint: .isDirectory)
        try LibraryArchive.write([RecordingSnapshot(recording: sample)], audioURLs: [sample.id: audio], appVersion: "test", to: package)
        #expect(SampleRecording.isPackage(package))
        #expect(!SampleRecording.isPackage(scratch))

        let outcome = try await SampleRecording.install(from: package, using: actions)
        #expect(outcome.importedIDs == [sample.id])
        let installed = try #require(try container.mainContext.fetch(FetchDescriptor<Recording>()).first)
        #expect(installed.source == .sample)
        #expect(installed.tags == ["contractor", "Sample"])
        #expect(installed.summaries.count == 1)
        #expect(installed.audioAvailable)
        #expect(await purchases.freeUsed == 1, "the bundled summary costs nothing")
        #expect(await pipeline.enqueued.isEmpty)
        #expect(LibraryCardModel(recording: installed).isSample)

        let again = try await SampleRecording.install(from: package, using: actions)
        #expect(again.importedIDs.isEmpty)
        #expect(again.skippedIDs == [sample.id])
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Recording>()) == 1)
    }
}
