import Foundation
import SwiftData
import Testing
@testable import VeraFlow

/// The queue and stage machine on fakes (SPEC §6.3). Real transcription is exercised on device.
@MainActor
struct LivePipelineCoordinatorTests {
    private struct Harness {
        let container: ModelContainer
        let storage: RecordingStorage
        let transcription: FakeTranscriptionService
        let background: FakeBackgroundProcessing
        let coordinator: LivePipelineCoordinator

        func cleanUp() {
            try? FileManager.default.removeItem(at: storage.rootDirectory)
        }

        /// A fresh context so we see what the coordinator saved, not a stale main-context object.
        func stage(of id: UUID) throws -> PipelineStage? {
            try fetch(id)?.stage
        }

        func fetch(_ id: UUID) throws -> Recording? {
            let context = ModelContext(container)
            var descriptor = FetchDescriptor<Recording>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first
        }

        @discardableResult
        func insert(title: String = "Meeting", stage: PipelineStage = .recorded, createdAt: Date = .now) throws -> UUID {
            let recording = Recording(title: title, createdAt: createdAt, stage: stage)
            container.mainContext.insert(recording)
            try container.mainContext.save()
            try storage.folder(for: recording.id)
            return recording.id
        }
    }

    private func makeHarness() throws -> Harness {
        let storage = RecordingStorage(rootDirectory: try TestAudioFiles.temporaryDirectory())
        let container = try ModelContainerFactory.makeInMemory()
        let transcription = FakeTranscriptionService()
        let background = FakeBackgroundProcessing()
        let coordinator = LivePipelineCoordinator(
            container: container,
            transcription: transcription,
            storage: storage,
            background: background
        )
        return Harness(container: container, storage: storage, transcription: transcription, background: background, coordinator: coordinator)
    }

    private func waitUntil(timeout: Duration = .seconds(3), _ condition: () throws -> Bool) async rethrows {
        let deadline = ContinuousClock.now + timeout
        while try !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("A recorded recording is transcribed into paragraphs and marked transcribed")
    func transcribes() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let id = try harness.insert()
        let events = await harness.coordinator.events()
        var seen: [PipelineEvent] = []
        let collector = Task { for await event in events { seen.append(event) } }

        await harness.coordinator.enqueue(recordingID: id)
        try await waitUntil { try harness.stage(of: id) == .transcribed }
        collector.cancel()

        let recording = try #require(try harness.fetch(id))
        #expect(recording.transcriptionEngine == .fake)
        #expect(recording.failureMessage == nil)
        let expected = Paragrapher.segments(from: FakeTranscriptionService.sampleWords)
        #expect(recording.orderedSegments.map(\.text) == expected.map(\.text))
        #expect(recording.orderedSegments.first?.words.count == expected.first?.words.count)
        #expect(await harness.transcription.transcribedURLs == [harness.storage.audioURL(for: id, fileName: "audio.aac")])
        #expect(await harness.background.runTitles == ["Processing recordings"])
        #expect(seen.contains(.stageChanged(recordingID: id, stage: .transcribing)))
        #expect(seen.contains(.progress(recordingID: id, stage: .transcribing, fraction: 1)))
        #expect(seen.last == .stageChanged(recordingID: id, stage: .transcribed))
    }

    @Test("A missing speech model is downloaded first, with its own event")
    func downloadsAssets() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        await harness.transcription.setAssetStatus(.downloadRequired)
        let id = try harness.insert()
        let events = await harness.coordinator.events()
        var seen: [PipelineEvent] = []
        let collector = Task { for await event in events { seen.append(event) } }

        await harness.coordinator.enqueue(recordingID: id)
        try await waitUntil { try harness.stage(of: id) == .transcribed }
        collector.cancel()

        #expect(await harness.transcription.prepareCount == 1)
        #expect(seen.contains(.preparingAssets(recordingID: id, stage: .transcribing, fraction: 1)))
    }

    @Test("Failure records the message and stage; Retry runs the stage again")
    func failureAndRetry() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        await harness.transcription.setError(.analysisFailed("boom"))
        let id = try harness.insert()

        await harness.coordinator.enqueue(recordingID: id)
        try await waitUntil { try harness.stage(of: id) == .failed }
        var recording = try #require(try harness.fetch(id))
        #expect(recording.failedStage == .transcribing)
        #expect(recording.failureMessage == "Transcription failed: boom")

        await harness.transcription.setError(nil)
        await harness.coordinator.retry(recordingID: id, from: .transcribing)
        try await waitUntil { try harness.stage(of: id) == .transcribed }
        recording = try #require(try harness.fetch(id))
        #expect(recording.failedStage == nil)
        #expect(recording.failureMessage == nil)
    }

    @Test("Launch resumes recorded and interrupted recordings oldest first and skips finished ones")
    func resumesPendingWork() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let base = Date(timeIntervalSince1970: 1_789_000_000)
        let newer = try harness.insert(title: "newer", stage: .recorded, createdAt: base.addingTimeInterval(60))
        let older = try harness.insert(title: "older", stage: .transcribing, createdAt: base)
        let done = try harness.insert(title: "done", stage: .transcribed, createdAt: base.addingTimeInterval(30))

        await harness.coordinator.resumePendingWork()
        try await waitUntil { try harness.stage(of: newer) == .transcribed && harness.stage(of: older) == .transcribed }

        let urls = await harness.transcription.transcribedURLs
        #expect(urls.map { $0.deletingLastPathComponent().lastPathComponent } == [older.uuidString, newer.uuidString])
        #expect(try harness.fetch(done)?.segments.isEmpty == true, "finished recordings are not reprocessed")
    }

    @Test("Cancelling the recording being processed leaves its row alone")
    func cancelCurrent() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        await harness.transcription.setDelay(.seconds(10))
        let id = try harness.insert()

        await harness.coordinator.enqueue(recordingID: id)
        try await waitUntil { try harness.stage(of: id) == .transcribing }
        await harness.coordinator.cancel(recordingID: id)
        try? await Task.sleep(for: .milliseconds(100))

        #expect(try harness.stage(of: id) == .transcribing, "the row is about to be deleted; nothing more is written")
        #expect(try harness.fetch(id)?.segments.isEmpty == true)
    }

    @Test("System expiration puts the recording back in the queue with stage recorded")
    func expiration() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        await harness.transcription.setDelay(.seconds(10))
        await harness.background.setExpireAfter(.milliseconds(100))
        let id = try harness.insert()

        await harness.coordinator.enqueue(recordingID: id)
        try await waitUntil { try harness.stage(of: id) == .transcribing }
        try await waitUntil { try harness.stage(of: id) == .recorded }

        #expect(try harness.fetch(id)?.failureMessage == nil)
    }
}
