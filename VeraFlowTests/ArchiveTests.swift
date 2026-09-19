import Foundation
import SwiftData
import Testing
@testable import VeraFlow

/// The `.veraflowarchive` package (v1.1 plan item 5): write, read, import, and the edge cases.
@MainActor
struct ArchiveTests {
    private struct Harness {
        let container: ModelContainer
        let storage: RecordingStorage
        let pipeline: FakePipelineCoordinator
        let actions: LibraryActions
        let scratch: URL
        var context: ModelContext { container.mainContext }

        func cleanUp() {
            try? FileManager.default.removeItem(at: scratch)
        }
    }

    private func makeHarness() throws -> Harness {
        let scratch = try TestAudioFiles.temporaryDirectory()
        let storage = RecordingStorage(rootDirectory: scratch.appending(path: "Recordings", directoryHint: .isDirectory))
        let pipeline = FakePipelineCoordinator()
        var services = AppServices.fakes(storage: storage)
        services.pipeline = pipeline
        let container = try ModelContainerFactory.makeInMemory()
        return Harness(container: container, storage: storage, pipeline: pipeline, actions: LibraryActions(context: container.mainContext, services: services), scratch: scratch)
    }

    /// The sample recording with a real (short) audio file in storage.
    private func insertSample(_ harness: Harness) throws -> Recording {
        let recording = PreviewData.sampleRecording()
        harness.context.insert(recording)
        try harness.context.save()
        try harness.storage.folder(for: recording.id)
        try TestAudioFiles.writeToneAAC(to: harness.storage.audioURL(for: recording.id, fileName: recording.audioFileName), seconds: 1)
        return recording
    }

    @Test("A snapshot carries every field and rebuilds an equal recording")
    func snapshotRoundTrip() throws {
        let recording = PreviewData.sampleRecording()
        recording.speakers.first { $0.key == "S2" }?.displayName = "Dana"
        recording.failedStage = .diarizing
        recording.failureMessage = "one voice"
        recording.transcriptionEngine = .speechTranscriber
        let snapshot = RecordingSnapshot(recording: recording)
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(RecordingSnapshot.self, from: data)
        #expect(decoded == snapshot)

        let rebuilt = decoded.makeRecording()
        #expect(rebuilt.id == recording.id)
        #expect(rebuilt.title == recording.title)
        #expect(rebuilt.orderedSegments.map(\.text) == recording.orderedSegments.map(\.text))
        #expect(rebuilt.orderedSegments.first?.words == recording.orderedSegments.first?.words)
        #expect(rebuilt.speakers.first { $0.key == "S2" }?.displayName == "Dana")
        #expect(rebuilt.bookmarks.map(\.note) == ["Permit question"])
        #expect(rebuilt.summaries.count == 1)
        #expect(try rebuilt.currentSummary?.payload() == (try recording.currentSummary?.payload()))
        #expect(rebuilt.failedStage == .diarizing)
        #expect(rebuilt.transcriptionEngine == .speechTranscriber)
        #expect(rebuilt.tags == ["contractor"])
        #expect(decoded.makeRecording(source: .sample, extraTags: ["Sample"]).source == .sample)
        #expect(decoded.makeRecording(source: .sample, extraTags: ["Sample"]).tags == ["contractor", "Sample"])
    }

    @Test("Export writes a package with the manifest, one folder per recording, and the audio; import restores it")
    func exportThenImport() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let recording = try insertSample(harness)
        let trashed = Recording(title: "gone", stage: .ready)
        trashed.deletedAt = .now
        harness.context.insert(trashed)
        try harness.context.save()

        let package = harness.scratch.appending(path: "Library.veraflowarchive", directoryHint: .isDirectory)
        try await harness.actions.exportArchive([recording, trashed], to: package)

        let (manifest, snapshots) = try LibraryArchive.read(package)
        #expect(manifest.formatVersion == LibraryArchive.formatVersion)
        #expect(manifest.recordingCount == 1, "Recently Deleted is not exported")
        #expect(snapshots.map(\.id) == [recording.id])
        #expect(LibraryArchive.audioURL(in: package, for: snapshots[0]) != nil)

        // Fresh library: everything comes back, audio included, and nothing is queued (it was ready).
        try await harness.actions.delete(recording)
        let outcome = try await harness.actions.importArchive(from: package)
        #expect(outcome.importedIDs == [recording.id])
        #expect(outcome.skippedIDs.isEmpty && outcome.missingAudioIDs.isEmpty)
        let restored = try #require(try harness.context.fetch(FetchDescriptor<Recording>()).first { $0.id == recording.id })
        #expect(restored.audioAvailable)
        #expect(restored.segments.count == 2)
        #expect(restored.summaries.count == 1)
        #expect(FileManager.default.fileExists(at: harness.storage.audioURL(for: recording.id, fileName: recording.audioFileName)))
        #expect(await harness.pipeline.enqueued.isEmpty)

        // Importing again skips it; with replace it is re-created.
        let again = try await harness.actions.importArchive(from: package)
        #expect(again.skippedIDs == [recording.id])
        #expect(again.importedIDs.isEmpty)
        let replaced = try await harness.actions.importArchive(from: package, replace: true)
        #expect(replaced.importedIDs == [recording.id])
        #expect(try harness.context.fetch(FetchDescriptor<Recording>()).filter { $0.id == recording.id }.count == 1)
    }

    @Test("A recording without audio imports with its transcript, is marked unavailable, and is not queued")
    func missingAudio() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let recording = PreviewData.sampleRecording()
        let package = harness.scratch.appending(path: "NoAudio.veraflowarchive", directoryHint: .isDirectory)
        try LibraryArchive.write([RecordingSnapshot(recording: recording)], audioURLs: [:], appVersion: "test", to: package)

        let outcome = try await harness.actions.importArchive(from: package)
        #expect(outcome.missingAudioIDs == [recording.id])
        let imported = try #require(try harness.context.fetch(FetchDescriptor<Recording>()).first)
        #expect(!imported.audioAvailable)
        #expect(imported.stage == .ready)
        #expect(imported.segments.count == 2)
        #expect(await harness.pipeline.enqueued.isEmpty)

        // Unfinished and without audio: nothing can transcribe it.
        let unfinished = Recording(title: "raw", stage: .recorded)
        let raw = harness.scratch.appending(path: "Raw.veraflowarchive", directoryHint: .isDirectory)
        try LibraryArchive.write([RecordingSnapshot(recording: unfinished)], audioURLs: [:], appVersion: "test", to: raw)
        try await harness.actions.importArchive(from: raw)
        let failed = try #require(try harness.context.fetch(FetchDescriptor<Recording>()).first { $0.id == unfinished.id })
        #expect(failed.stage == .failed)
        #expect(failed.failureMessage == LibraryActions.missingAudioMessage)
    }

    @Test("Unfinished recordings with audio are queued after import; a newer format is refused")
    func queuedAndRefused() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let unfinished = Recording(title: "raw", stage: .recorded)
        harness.context.insert(unfinished)
        try harness.context.save()
        try harness.storage.folder(for: unfinished.id)
        try TestAudioFiles.writeToneAAC(to: harness.storage.audioURL(for: unfinished.id, fileName: unfinished.audioFileName), seconds: 1)
        let package = harness.scratch.appending(path: "Raw.veraflowarchive", directoryHint: .isDirectory)
        try await harness.actions.exportArchive([unfinished], to: package)
        try await harness.actions.delete(unfinished)

        try await harness.actions.importArchive(from: package)
        #expect(await harness.pipeline.enqueued == [unfinished.id])

        let manifestURL = package.appending(path: LibraryArchive.manifestName)
        let bumped = ArchiveManifest(formatVersion: LibraryArchive.formatVersion + 1, appVersion: "9", createdAt: .now, recordingCount: 1)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(bumped).write(to: manifestURL)
        await #expect(throws: ArchiveError.newerFormat(LibraryArchive.formatVersion + 1)) {
            try await harness.actions.importArchive(from: package)
        }
        await #expect(throws: ArchiveError.notAnArchive) {
            try await harness.actions.importArchive(from: harness.scratch)
        }
    }

    @Test("Package names and storage usage")
    func namesAndUsage() throws {
        let name = LibraryArchive.packageName(for: "Kitchen: remodel", createdAt: Date(timeIntervalSince1970: 1_789_000_000), calendar: Calendar(identifier: .gregorian))
        #expect(name.hasSuffix(" Kitchen  remodel.veraflowarchive"))
        #expect(LibraryArchive.isArchive(URL(filePath: "/x/Library.VeraFlowArchive")))
        #expect(!LibraryArchive.isArchive(URL(filePath: "/x/audio.m4a")))

        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let live = UUID()
        let trashed = UUID()
        try harness.storage.folder(for: live)
        try harness.storage.folder(for: trashed)
        try Data(repeating: 1, count: 1_000).write(to: harness.storage.audioURL(for: live, fileName: "audio.aac"))
        try Data(repeating: 1, count: 500).write(to: harness.storage.audioURL(for: trashed, fileName: "audio.aac"))
        let usage = StorageUsage.compute(recordings: [(live, false), (trashed, true), (UUID(), false)], storage: harness.storage)
        #expect(usage.liveBytes == 1_000)
        #expect(usage.trashedBytes == 500)
        #expect(usage.totalBytes == 1_500)
    }
}
