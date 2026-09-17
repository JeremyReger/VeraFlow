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
        let diarization: FakeDiarizationService
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

    private func makeHarness(speakerHint: SpeakerCountHint = .automatic) throws -> Harness {
        let storage = RecordingStorage(rootDirectory: try TestAudioFiles.temporaryDirectory())
        let container = try ModelContainerFactory.makeInMemory()
        let transcription = FakeTranscriptionService()
        let diarization = FakeDiarizationService()
        let background = FakeBackgroundProcessing()
        let coordinator = LivePipelineCoordinator(
            container: container,
            transcription: transcription,
            diarization: diarization,
            aligner: LiveTranscriptAligner(),
            storage: storage,
            background: background,
            speakerHint: { speakerHint }
        )
        return Harness(
            container: container,
            storage: storage,
            transcription: transcription,
            diarization: diarization,
            background: background,
            coordinator: coordinator
        )
    }

    private func waitUntil(timeout: Duration = .seconds(3), _ condition: () throws -> Bool) async rethrows {
        let deadline = ContinuousClock.now + timeout
        while try !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("A recorded recording is transcribed, then split by speaker and marked diarized")
    func transcribesAndLabels() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let id = try harness.insert()
        let events = await harness.coordinator.events()
        var seen: [PipelineEvent] = []
        let collector = Task { for await event in events { seen.append(event) } }

        await harness.coordinator.enqueue(recordingID: id)
        try await waitUntil { try harness.stage(of: id) == .diarized }
        collector.cancel()

        let recording = try #require(try harness.fetch(id))
        #expect(recording.transcriptionEngine == .fake)
        #expect(recording.failureMessage == nil)
        #expect(recording.failedStage == nil)
        // The sample turns split the sample sentence pair between two speakers.
        #expect(recording.orderedSegments.map(\.text) == [
            "We need the permit before we pour the footer.",
            "I will call the county on Monday.",
        ])
        #expect(recording.orderedSegments.map(\.speakerKey) == ["S1", "S2"])
        #expect(recording.orderedSegments.map { $0.words.count } == [9, 7])
        #expect(recording.speakers.sorted { $0.key < $1.key }.map(\.displayName) == ["Speaker 1", "Speaker 2"])
        #expect(await harness.transcription.transcribedURLs == [harness.storage.audioURL(for: id, fileName: "audio.aac")])
        #expect(await harness.diarization.diarizedURLs == [harness.storage.audioURL(for: id, fileName: "audio.aac")])
        #expect(await harness.background.runTitles == ["Processing recordings"])
        #expect(seen.contains(.stageChanged(recordingID: id, stage: .transcribing)))
        #expect(seen.contains(.progress(recordingID: id, stage: .transcribing, fraction: 1)))
        #expect(seen.contains(.stageChanged(recordingID: id, stage: .transcribed)))
        #expect(seen.contains(.stageChanged(recordingID: id, stage: .diarizing)))
        #expect(seen.contains(.progress(recordingID: id, stage: .diarizing, fraction: 1)))
        #expect(seen.last == .stageChanged(recordingID: id, stage: .diarized))
    }

    @Test("Missing speaker-label models are downloaded first; the Settings hint reaches the diarizer")
    func downloadsDiarizerModels() async throws {
        let harness = try makeHarness(speakerHint: SpeakerCountHint(exact: 2))
        defer { harness.cleanUp() }
        await harness.diarization.setReady(false)
        let id = try harness.insert()
        let events = await harness.coordinator.events()
        var seen: [PipelineEvent] = []
        let collector = Task { for await event in events { seen.append(event) } }

        await harness.coordinator.enqueue(recordingID: id)
        try await waitUntil { try harness.stage(of: id) == .diarized }
        collector.cancel()

        #expect(await harness.diarization.prepareCount == 1)
        #expect(await harness.diarization.hints == [SpeakerCountHint(exact: 2)])
        #expect(seen.contains(.preparingAssets(recordingID: id, stage: .diarizing, fraction: 1)))
    }

    @Test("Diarization failure is non-fatal: one speaker, a Retry reason, and Retry relabels")
    func diarizationFailureIsNonFatal() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        await harness.diarization.setError(.processingFailed("no models"))
        let id = try harness.insert()
        let events = await harness.coordinator.events()
        var seen: [PipelineEvent] = []
        let collector = Task { for await event in events { seen.append(event) } }

        await harness.coordinator.enqueue(recordingID: id)
        try await waitUntil { try harness.stage(of: id) == .diarized }
        collector.cancel()

        var recording = try #require(try harness.fetch(id))
        #expect(recording.failedStage == .diarizing)
        #expect(recording.failureMessage == "Speaker labeling failed: no models")
        #expect(recording.speakers.map(\.key) == ["S1"])
        #expect(recording.orderedSegments.count == 1)
        #expect(recording.orderedSegments.allSatisfy { $0.speakerKey == "S1" })
        #expect(seen.contains(.failed(recordingID: id, stage: .diarizing, message: "Speaker labeling failed: no models")))

        await harness.diarization.setError(nil)
        await harness.coordinator.retry(recordingID: id, from: .diarizing)
        try await waitUntil { try harness.fetch(id)?.speakers.count == 2 }
        recording = try #require(try harness.fetch(id))
        #expect(recording.stage == .diarized)
        #expect(recording.failedStage == nil)
        #expect(recording.failureMessage == nil)
        #expect(await harness.transcription.transcribedURLs.count == 1, "Retry from diarizing does not transcribe again")
    }

    @Test("An edited transcript is labeled in place instead of being re-split")
    func editedTranscriptKeepsText() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let recording = Recording(title: "Edited", stage: .transcribed)
        recording.segments = [
            TranscriptSegment(
                index: 0, start: 0, end: 6.4, text: "Corrected by hand",
                originalText: FakeTranscriptionService.sampleWords.map(\.text).joined(separator: " "),
                words: FakeTranscriptionService.sampleWords
            ),
        ]
        recording.speakers = [Speaker(key: "S1", displayName: "Jeremy", colorIndex: 0)]
        harness.container.mainContext.insert(recording)
        try harness.container.mainContext.save()
        try harness.storage.folder(for: recording.id)
        let id = recording.id

        await harness.coordinator.enqueue(recordingID: id)
        try await waitUntil { try harness.stage(of: id) == .diarized }

        let saved = try #require(try harness.fetch(id))
        #expect(saved.orderedSegments.map(\.text) == ["Corrected by hand"])
        #expect(saved.orderedSegments.first?.isEdited == true)
        // 9 of 16 words fall in the first turn, so the paragraph goes to S1; the name survives.
        #expect(saved.orderedSegments.first?.speakerKey == "S1")
        #expect(saved.speakers.map(\.displayName) == ["Jeremy"])
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
        try await waitUntil { try harness.stage(of: id) == .diarized }
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
        try await waitUntil { try harness.stage(of: id) == .diarized }
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
        let done = try harness.insert(title: "done", stage: .diarized, createdAt: base.addingTimeInterval(30))

        await harness.coordinator.resumePendingWork()
        try await waitUntil { try harness.stage(of: newer) == .diarized && harness.stage(of: older) == .diarized }

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
