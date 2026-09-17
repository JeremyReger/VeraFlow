import Foundation
import SwiftData
import Testing
@testable import VeraFlow

@MainActor
struct LibraryActionsTests {
    private struct Harness {
        let container: ModelContainer
        let context: ModelContext
        let storage: RecordingStorage
        let pipeline: FakePipelineCoordinator
        let importer: FakeAudioImportService
        let actions: LibraryActions

        func cleanUp() {
            try? FileManager.default.removeItem(at: storage.rootDirectory.deletingLastPathComponent())
        }
    }

    private func makeHarness() throws -> Harness {
        let base = try TestAudioFiles.temporaryDirectory()
        let storage = RecordingStorage(rootDirectory: base.appending(path: "Recordings", directoryHint: .isDirectory))
        var services = AppServices.fakes(storage: storage)
        let pipeline = FakePipelineCoordinator()
        let importer = FakeAudioImportService(fixedDuration: 90)
        services.pipeline = pipeline
        services.importer = importer
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let actions = LibraryActions(context: context, services: services)
        return Harness(container: container, context: context, storage: storage, pipeline: pipeline, importer: importer, actions: actions)
    }

    private func insertRecording(_ harness: Harness, title: String = "Meeting") throws -> Recording {
        let recording = Recording(title: title, stage: .recorded)
        harness.context.insert(recording)
        try harness.context.save()
        return recording
    }

    @Test("Rename trims whitespace and rejects an empty title")
    func rename() throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let recording = try insertRecording(harness)

        try harness.actions.rename(recording, to: "  Site visit  ")
        #expect(recording.title == "Site visit")

        #expect(throws: LibraryActionError.emptyTitle) {
            try harness.actions.rename(recording, to: "   ")
        }
        #expect(recording.title == "Site visit")
    }

    @Test("Favorite toggles and persists")
    func favorite() throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let recording = try insertRecording(harness)

        try harness.actions.toggleFavorite(recording)
        #expect(recording.isFavorite)
        try harness.actions.toggleFavorite(recording)
        #expect(!recording.isFavorite)
    }

    @Test("Tags are trimmed, de-duplicated case-insensitively, and blanks dropped")
    func tags() throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let recording = try insertRecording(harness)

        try harness.actions.setTags(recording, to: [" client ", "", "Client", "contractor", "contractor "])
        #expect(recording.tags == ["client", "contractor"])
        #expect(LibraryActions.normalized([]) == [])
    }

    @Test("Delete removes the row, its folder, and cancels pipeline work")
    func delete() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let recording = try insertRecording(harness)
        let id = recording.id
        try harness.storage.folder(for: id)
        try Data("x".utf8).write(to: harness.storage.audioURL(for: id, fileName: "audio.aac"))

        try await harness.actions.delete(recording)

        #expect(try harness.context.fetchCount(FetchDescriptor<Recording>()) == 0)
        #expect(try harness.storage.existingFolderIDs().isEmpty)
        #expect(await harness.pipeline.cancelled == [id])
    }

    @Test("Import creates an imported row with the file's duration and queues processing")
    func importAudio() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let source = harness.storage.rootDirectory.deletingLastPathComponent().appending(path: "Site walk_through.wav")
        try Data("pretend audio".utf8).write(to: source)

        let recording = try await harness.actions.importAudio(from: source)

        #expect(recording.title == "Site walk through")
        #expect(recording.source == .imported)
        #expect(recording.stage == .recorded)
        #expect(recording.duration == 90)
        #expect(recording.audioFileName == "audio.wav")
        #expect(FileManager.default.fileExists(at: harness.storage.audioURL(for: recording.id, fileName: "audio.wav")))
        #expect(try harness.context.fetchCount(FetchDescriptor<Recording>()) == 1)
        #expect(await harness.pipeline.enqueued == [recording.id])
        #expect(FileManager.default.fileExists(at: source), "Non-Inbox sources are left alone")
    }

    @Test("A failed import leaves no row and no folder")
    func importFailure() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let source = harness.storage.rootDirectory.deletingLastPathComponent().appending(path: "notes.txt")
        try Data("x".utf8).write(to: source)

        await #expect(throws: AudioImportError.unsupportedType("txt")) {
            _ = try await harness.actions.importAudio(from: source)
        }
        #expect(try harness.context.fetchCount(FetchDescriptor<Recording>()) == 0)
        #expect(try harness.storage.existingFolderIDs().isEmpty)
    }

    @Test("Files handed over via the share sheet (Inbox) are removed after import")
    func inboxCleanup() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let inbox = harness.storage.rootDirectory.deletingLastPathComponent().appending(path: "Inbox", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let source = inbox.appending(path: "Voice Memo.m4a")
        try Data("pretend audio".utf8).write(to: source)

        let recording = try await harness.actions.importAudio(from: source)
        #expect(recording.title == "Voice Memo")
        #expect(!FileManager.default.fileExists(at: source))
        #expect(LibraryActions.isInboxURL(source))
        #expect(!LibraryActions.isInboxURL(URL(filePath: "/tmp/Voice Memo.m4a")))
    }

    @Test("AppState queues open-URL imports and hands them over once")
    func pendingImports() {
        let state = AppState(services: .fakes())
        state.enqueueImport(URL(filePath: "/tmp/a.m4a"))
        state.enqueueImport(URL(string: "https://example.com/a.m4a")!)
        #expect(state.pendingImportURLs.count == 1)
        #expect(state.takePendingImports().count == 1)
        #expect(state.pendingImportURLs.isEmpty)
        #expect(state.takePendingImports().isEmpty)
    }
}
