import Foundation
import SwiftData
import Testing
@testable import VeraFlow

@MainActor
struct RecorderViewModelTests {
    private struct Harness {
        let viewModel: RecorderViewModel
        let recorder: FakeAudioRecorderService
        let pipeline: FakePipelineCoordinator
        let activity: FakeRecordingActivityService
        let storage: RecordingStorage
        /// Kept alive for the test's duration; the context does not retain it.
        let container: ModelContainer
        let context: ModelContext

        func cleanUp() {
            try? FileManager.default.removeItem(at: storage.rootDirectory)
        }
    }

    private func makeHarness(permissionGranted: Bool = true) throws -> Harness {
        let storage = RecordingStorage(rootDirectory: try TestAudioFiles.temporaryDirectory())
        var services = AppServices.fakes(storage: storage)
        let recorder = FakeAudioRecorderService(permissionGranted: permissionGranted)
        let pipeline = FakePipelineCoordinator()
        let activity = FakeRecordingActivityService()
        services.recorder = recorder
        services.pipeline = pipeline
        services.activity = activity
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let fixedNow = Date(timeIntervalSince1970: 1_789_000_000)
        let viewModel = RecorderViewModel(services: services, context: context, now: { fixedNow })
        return Harness(viewModel: viewModel, recorder: recorder, pipeline: pipeline, activity: activity, storage: storage, container: container, context: context)
    }

    /// Waits for an async condition driven by the fake's streams.
    private func waitUntil(timeout: Duration = .seconds(2), _ condition: @MainActor () -> Bool) async {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("Start creates a .recording row, its folder, and starts the recorder there")
    func start() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let viewModel = harness.viewModel

        await viewModel.start()

        #expect(viewModel.phase == .recording)
        let recording = try #require(viewModel.recording)
        #expect(recording.stage == .recording)
        #expect(recording.title.hasPrefix("Meeting · "))
        #expect(viewModel.draftTitle == recording.title)

        let expectedURL = harness.storage.audioURL(for: recording.id, fileName: recording.audioFileName)
        #expect(await harness.recorder.startedURL == expectedURL)
        #expect(FileManager.default.fileExists(at: expectedURL.deletingLastPathComponent()))
        #expect(try harness.context.fetchCount(FetchDescriptor<Recording>()) == 1)
    }

    @Test("Denied permission moves to permissionDenied without creating a row")
    func permissionDenied() async throws {
        let harness = try makeHarness(permissionGranted: false)
        defer { harness.cleanUp() }

        await harness.viewModel.start()

        #expect(harness.viewModel.phase == .permissionDenied)
        #expect(harness.viewModel.recording == nil)
        #expect(try harness.context.fetchCount(FetchDescriptor<Recording>()) == 0)
    }

    @Test("Pause and resume follow the recorder")
    func pauseResume() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let viewModel = harness.viewModel

        await viewModel.start()
        await viewModel.pause()
        #expect(viewModel.phase == .paused)
        #expect(await harness.recorder.snapshot.status == .paused)

        await viewModel.resume()
        #expect(viewModel.phase == .recording)
        #expect(await harness.recorder.snapshot.status == .recording)
    }

    @Test("Snapshots update the timer and level")
    func snapshots() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let viewModel = harness.viewModel

        await viewModel.start()
        await harness.recorder.advance(by: 12.5, level: 0.7)
        await waitUntil { viewModel.snapshot.elapsed == 12.5 }

        #expect(viewModel.snapshot.elapsed == 12.5)
        #expect(viewModel.snapshot.level == 0.7)
    }

    @Test("Waveform history keeps the newest levels and is capped")
    func levelHistory() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let viewModel = harness.viewModel

        await viewModel.start()
        for step in 0..<(RecorderViewModel.waveformSampleCount + 20) {
            await harness.recorder.advance(by: 0.1, level: Float(step % 10) / 10)
        }
        await waitUntil { viewModel.snapshot.elapsed > Double(RecorderViewModel.waveformSampleCount + 19) * 0.1 - 0.001 }
        // The stream may still be draining; wait for the history to fill.
        await waitUntil { viewModel.levelHistory.count == RecorderViewModel.waveformSampleCount && viewModel.levelHistory.last?.level == 0.9 }

        #expect(viewModel.levelHistory.count == RecorderViewModel.waveformSampleCount)
        #expect(viewModel.levelHistory.last?.level == 0.9)
        #expect(viewModel.levelHistory.contains { $0.isBookmark } == false)

        await viewModel.addBookmark()
        #expect(viewModel.levelHistory.last?.isBookmark == true)

        await viewModel.pause()
        await harness.recorder.advance(by: 0.1, level: 0.5) // ignored while paused
        await viewModel.resume()
        await harness.recorder.advance(by: 0.1, level: 0.3)
        await waitUntil { viewModel.levelHistory.last?.level == 0.3 }
        #expect(viewModel.levelHistory.last?.level == 0.3)
        #expect(viewModel.levelHistory.last?.isBookmark == false)
        #expect(viewModel.levelHistory.filter { $0.isBookmark }.count == 1)
    }

    @Test("Bookmarks are stamped with the recorder's current time")
    func bookmarks() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let viewModel = harness.viewModel

        await viewModel.start()
        await harness.recorder.advance(by: 30)
        await viewModel.addBookmark()
        await harness.recorder.advance(by: 15)
        await viewModel.addBookmark(note: "Decision")

        #expect(viewModel.bookmarkCount == 2)
        let recording = try #require(viewModel.recording)
        let times = recording.bookmarks.map(\.time).sorted()
        #expect(times == [30, 45])
        #expect(recording.bookmarks.first { $0.time == 45 }?.note == "Decision")
    }

    @Test("A call pauses, adds an Interrupted bookmark, then offers to resume")
    func interruption() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let viewModel = harness.viewModel

        await viewModel.start()
        await harness.recorder.advance(by: 20)
        await harness.recorder.simulate(.began)
        await waitUntil { viewModel.bookmarkCount == 1 }

        #expect(viewModel.phase == .paused)
        let recording = try #require(viewModel.recording)
        #expect(recording.bookmarks.first?.note == "Interrupted")
        #expect(recording.bookmarks.first?.time == 20)

        await harness.recorder.simulate(.ended(shouldResume: true))
        await waitUntil { viewModel.isAskingToResume }
        #expect(viewModel.isAskingToResume)

        await viewModel.answerResumePrompt(resume: true)
        #expect(!viewModel.isAskingToResume)
        #expect(viewModel.phase == .recording)
    }

    @Test("Route change and low disk space show a notice without stopping")
    func routeChangeAndLowDisk() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let viewModel = harness.viewModel

        await viewModel.start()
        await harness.recorder.simulate(.routeChanged)
        await waitUntil { viewModel.notice != nil }
        #expect(viewModel.notice?.contains("Headset") == true)
        #expect(viewModel.phase == .recording)

        await harness.recorder.simulate(.lowDiskSpace(availableBytes: 400_000_000))
        await waitUntil { viewModel.lowDiskBytes != nil }
        #expect(viewModel.lowDiskBytes == 400_000_000)
        #expect(viewModel.phase == .recording)
    }

    @Test("Disk full stops the recording and moves to naming")
    func diskFull() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let viewModel = harness.viewModel

        await viewModel.start()
        await harness.recorder.advance(by: 5)
        await harness.recorder.simulate(.diskFull(availableBytes: 50_000_000))
        await waitUntil { viewModel.phase == .naming }

        #expect(viewModel.phase == .naming)
        #expect(viewModel.recording?.duration == 5)
        #expect(await harness.recorder.snapshot.status == .idle)
    }

    @Test("Stop then save finalizes the row and enqueues the pipeline")
    func stopAndSave() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let viewModel = harness.viewModel

        await viewModel.start()
        await harness.recorder.advance(by: 90)
        await viewModel.stop()

        #expect(viewModel.phase == .naming)
        let recording = try #require(viewModel.recording)
        #expect(recording.duration == 90)
        #expect(recording.stage == .recording)

        viewModel.draftTitle = "  Site visit  "
        await viewModel.save()

        #expect(viewModel.phase == .saved(recordingID: recording.id))
        #expect(recording.title == "Site visit")
        #expect(recording.stage == .recorded)
        #expect(await harness.pipeline.enqueued == [recording.id])
    }

    @Test("An empty title falls back to the suggested one")
    func emptyTitle() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let viewModel = harness.viewModel

        await viewModel.start()
        await viewModel.stop()
        viewModel.draftTitle = "   "
        await viewModel.save()

        #expect(viewModel.recording?.title.hasPrefix("Meeting · ") == true)
    }

    @Test("Input selection is forwarded to the recorder")
    func inputs() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let viewModel = harness.viewModel

        await viewModel.loadInputs()
        #expect(viewModel.inputs.count == 2)

        await viewModel.selectInput(id: "airpods")
        #expect(viewModel.selectedInputID == "airpods")
        #expect(await harness.recorder.selectedInputID == "airpods")

        await viewModel.selectInput(id: "missing")
        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.selectedInputID == "airpods")
    }

    @Test("The Live Activity follows start, pause, bookmark, resume, and stop")
    func liveActivity() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let viewModel = harness.viewModel
        let activity = harness.activity
        let fixedNow = Date(timeIntervalSince1970: 1_789_000_000)

        await viewModel.start()
        let recording = try #require(viewModel.recording)
        #expect(await activity.startedRecordingID == recording.id)
        #expect(await activity.startedTitle == recording.title)
        let initial = try #require(await activity.latestState)
        #expect(initial.startedAt == fixedNow)
        #expect(!initial.isPaused)
        #expect(initial.bookmarkCount == 0)

        await harness.recorder.advance(by: 30)
        await waitUntil { viewModel.snapshot.elapsed >= 30 }
        await viewModel.addBookmark()
        let afterBookmark = try #require(await activity.latestState)
        #expect(afterBookmark.bookmarkCount == 1)
        #expect(afterBookmark.startedAt == fixedNow.addingTimeInterval(-30))

        await viewModel.pause()
        let paused = try #require(await activity.latestState)
        #expect(paused.isPaused)
        #expect(paused.pausedAt == fixedNow)

        await viewModel.resume()
        let resumed = try #require(await activity.latestState)
        #expect(!resumed.isPaused)

        await viewModel.stop()
        #expect(await activity.endCount == 1)
        #expect(await activity.isActive == false)
    }

    @Test("An interruption pauses the Live Activity too")
    func liveActivityInterruption() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let viewModel = harness.viewModel

        await viewModel.start()
        await harness.recorder.simulate(.began)
        await waitUntil { viewModel.phase == .paused }
        await waitUntil { viewModel.bookmarkCount == 1 }

        let state = try #require(await harness.activity.latestState)
        #expect(state.isPaused)
        #expect(state.bookmarkCount == 1)
    }
}
