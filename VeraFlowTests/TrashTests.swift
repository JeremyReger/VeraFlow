import Foundation
import SwiftData
import Testing
@testable import VeraFlow

/// Recently Deleted (v1.1 plan item 10): trash, restore, permanent delete, and the launch sweep.
@MainActor
struct TrashTests {
    /// Nested types don't inherit the outer actor isolation; the harness touches `mainContext`.
    @MainActor
    private struct Harness {
        let container: ModelContainer
        let storage: RecordingStorage
        let pipeline: FakePipelineCoordinator
        let actions: LibraryActions
        var context: ModelContext { container.mainContext }

        func cleanUp() {
            try? FileManager.default.removeItem(at: storage.rootDirectory)
        }
    }

    private func makeHarness() throws -> Harness {
        let storage = RecordingStorage(rootDirectory: try TestAudioFiles.temporaryDirectory())
        let pipeline = FakePipelineCoordinator()
        var services = AppServices.fakes(storage: storage)
        services.pipeline = pipeline
        let container = try ModelContainerFactory.makeInMemory()
        return Harness(container: container, storage: storage, pipeline: pipeline, actions: LibraryActions(context: container.mainContext, services: services))
    }

    @Test("Trash keeps the row and the audio, cancels queued work, and hides the recording from the Library")
    func trashKeepsData() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let recording = Recording(title: "Meeting", stage: .transcribing, tags: ["client"])
        harness.context.insert(recording)
        try harness.context.save()
        try harness.storage.folder(for: recording.id)

        try await harness.actions.trash(recording)

        #expect(recording.isTrashed)
        #expect(await harness.pipeline.cancelled == [recording.id])
        #expect(try harness.storage.existingFolderIDs() == [recording.id])
        #expect(LibraryFilter().apply(to: [recording]).isEmpty)
        #expect(LibraryFilter.allTags(in: [recording]).isEmpty)
        var starred = LibraryFilter()
        starred.favoritesOnly = true
        recording.isFavorite = true
        #expect(starred.apply(to: [recording]).isEmpty)
    }

    @Test("Restore brings the recording back and re-queues processing that was cut short")
    func restoreRequeues() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let unfinished = Recording(title: "Unfinished", stage: .recorded)
        let finished = Recording(title: "Finished", stage: .ready)
        harness.context.insert(unfinished)
        harness.context.insert(finished)
        try harness.context.save()
        try await harness.actions.trash(unfinished)
        try await harness.actions.trash(finished)

        try await harness.actions.restore(unfinished)
        try await harness.actions.restore(finished)

        #expect(!unfinished.isTrashed && !finished.isTrashed)
        #expect(await harness.pipeline.enqueued == [unfinished.id])
        #expect(LibraryFilter().apply(to: [unfinished, finished]).count == 2)
    }

    @Test("Delete Now and Empty remove rows and folders for good")
    func permanentDelete() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let first = Recording(title: "one", stage: .ready)
        let second = Recording(title: "two", stage: .ready)
        let kept = Recording(title: "kept", stage: .ready)
        for recording in [first, second, kept] {
            harness.context.insert(recording)
            try harness.storage.folder(for: recording.id)
        }
        try harness.context.save()
        try await harness.actions.trash(first)
        try await harness.actions.trash(second)

        try await harness.actions.delete(first)
        #expect(try harness.context.fetchCount(FetchDescriptor<Recording>()) == 2)
        #expect(!(try harness.storage.existingFolderIDs()).contains(first.id))

        try await harness.actions.emptyTrash()
        let remaining = try harness.context.fetch(FetchDescriptor<Recording>())
        #expect(remaining.map(\.title) == ["kept"])
        #expect(try harness.storage.existingFolderIDs() == [kept.id])
    }

    @Test("The sweep removes only recordings past the retention, folders included")
    func sweep() throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let old = Recording(title: "old", stage: .ready)
        old.deletedAt = now.addingTimeInterval(-TrashPolicy.retention - 60)
        let recent = Recording(title: "recent", stage: .ready)
        recent.deletedAt = now.addingTimeInterval(-TrashPolicy.retention + 3_600)
        let live = Recording(title: "live", stage: .ready)
        for recording in [old, recent, live] {
            harness.context.insert(recording)
            try harness.storage.folder(for: recording.id)
        }
        try harness.context.save()

        let removed = try TrashSweeper(context: harness.context, storage: harness.storage).sweep(now: now)

        #expect(removed == [old.id])
        #expect(Set(try harness.context.fetch(FetchDescriptor<Recording>()).map(\.title)) == ["recent", "live"])
        #expect(Set(try harness.storage.existingFolderIDs()) == [recent.id, live.id])
        #expect(TrashPolicy.daysRemaining(deletedAt: recent.deletedAt!, now: now) == 1)
        #expect(TrashPolicy.daysRemaining(deletedAt: now, now: now) == 30)
        #expect(TrashPolicy.daysRemaining(deletedAt: old.deletedAt!, now: now) == 0)
        #expect(try TrashSweeper(context: harness.context, storage: harness.storage).sweep(now: now).isEmpty, "nothing left to sweep")
    }

    @Test("Delete all data empties Recently Deleted too")
    func deleteAllIncludesTrash() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let trashed = Recording(title: "trashed", stage: .ready)
        harness.context.insert(trashed)
        try harness.context.save()
        try await harness.actions.trash(trashed)
        try await harness.actions.deleteAll()
        #expect(try harness.context.fetchCount(FetchDescriptor<Recording>()) == 0)
    }
}
