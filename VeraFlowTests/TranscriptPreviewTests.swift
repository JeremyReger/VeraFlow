import Foundation
import SwiftData
import Testing
@testable import VeraFlow

/// Words while recording (v1.1 plan item 4): the reducer, and the view model's rules for when
/// the preview runs.
@MainActor
struct TranscriptPreviewTests {
    // MARK: Reducer

    @Test("Volatile text replaces the current line; a finalized line is appended and clears it")
    func reducer() {
        var state = PreviewState()
        PreviewReducer.apply(.volatile("We need"), to: &state)
        PreviewReducer.apply(.volatile("We need the permit"), to: &state)
        #expect(state.volatile == "We need the permit")
        #expect(state.currentLine == "We need the permit")
        #expect(state.previousLine == "")

        PreviewReducer.apply(.finalized("We need the permit before we pour."), to: &state)
        #expect(state.volatile == "")
        #expect(state.finalized == ["We need the permit before we pour."])
        #expect(state.currentLine == "We need the permit before we pour.")

        PreviewReducer.apply(.volatile("I will"), to: &state)
        #expect(state.previousLine == "We need the permit before we pour.")
        #expect(state.currentLine == "I will")

        PreviewReducer.apply(.finalized("  \n "), to: &state)
        #expect(state.finalized.count == 1, "blank finalized text adds nothing")
        #expect(state.volatile == "")
    }

    @Test("History keeps the last five lines; the previous line is the one before the current")
    func history() {
        var state = PreviewState()
        for index in 1...8 {
            PreviewReducer.apply(.finalized("Line \(index)"), to: &state)
        }
        #expect(state.finalized == ["Line 4", "Line 5", "Line 6", "Line 7", "Line 8"])
        #expect(state.currentLine == "Line 8")
        #expect(state.previousLine == "Line 7")
        #expect(!state.isEmpty)
        #expect(PreviewState().isEmpty)
    }

    // MARK: View model

    private struct Harness {
        let viewModel: RecorderViewModel
        let recorder: FakeAudioRecorderService
        let preview: FakeTranscriptPreviewService
        let defaults: UserDefaults
        let suite: String
        let storage: RecordingStorage
        let container: ModelContainer

        func cleanUp() {
            try? FileManager.default.removeItem(at: storage.rootDirectory)
            defaults.removePersistentDomain(forName: suite)
        }
    }

    private final class ThermalBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _state: ProcessInfo.ThermalState = .nominal
        var state: ProcessInfo.ThermalState {
            get { lock.withLock { _state } }
            set { lock.withLock { _state = newValue } }
        }
    }

    private func makeHarness(thermal: ThermalBox = ThermalBox(), previewAvailable: Bool = true) throws -> Harness {
        let storage = RecordingStorage(rootDirectory: try TestAudioFiles.temporaryDirectory())
        var services = AppServices.fakes(storage: storage)
        let recorder = FakeAudioRecorderService()
        let preview = FakeTranscriptPreviewService(available: previewAvailable)
        services.recorder = recorder
        services.transcriptPreview = preview
        let container = try ModelContainerFactory.makeInMemory()
        let suite = "TranscriptPreviewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let viewModel = RecorderViewModel(services: services, context: container.mainContext, defaults: defaults, thermalState: { thermal.state })
        return Harness(viewModel: viewModel, recorder: recorder, preview: preview, defaults: defaults, suite: suite, storage: storage, container: container)
    }

    private func waitUntil(timeout: Duration = .seconds(2), _ condition: @MainActor () -> Bool) async {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("Start opens the preview, attaches the recorder sink, and events reach the screen; Stop closes it")
    func startAndStop() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let viewModel = harness.viewModel

        await viewModel.start()
        #expect(viewModel.isPreviewOn)
        #expect(await harness.preview.startCount == 1)
        #expect(await harness.recorder.hasPreviewSink)

        await harness.preview.emit(.volatile("We need"))
        await waitUntil { viewModel.preview.currentLine == "We need" }
        #expect(viewModel.preview.currentLine == "We need")
        await harness.preview.emit(.finalized("We need the permit."))
        await waitUntil { viewModel.preview.finalized.count == 1 }
        #expect(viewModel.preview.finalized == ["We need the permit."])

        // Pause keeps the analyzer; the recorder simply stops feeding it.
        await viewModel.pause()
        #expect(viewModel.isPreviewOn)
        await viewModel.resume()

        await viewModel.stop()
        #expect(!viewModel.isPreviewOn)
        #expect(await harness.preview.stopCount == 1)
        #expect(await !harness.recorder.hasPreviewSink)
        #expect(viewModel.preview.isEmpty)
    }

    @Test("The setting off, or no on-device transcriber, means no preview")
    func offOrUnavailable() async throws {
        let off = try makeHarness()
        defer { off.cleanUp() }
        AppPreferences.setShowsLiveTranscript(false, in: off.defaults)
        await off.viewModel.start()
        #expect(!off.viewModel.isPreviewOn)
        #expect(await off.preview.startCount == 0)
        await off.viewModel.stop()

        let unavailable = try makeHarness(previewAvailable: false)
        defer { unavailable.cleanUp() }
        await unavailable.viewModel.start()
        #expect(!unavailable.viewModel.isPreviewOn)
        #expect(unavailable.viewModel.previewNotice == "Live words need the on-device speech model.")
        #expect(await unavailable.preview.startCount == 0)
        await unavailable.viewModel.stop()
    }

    @Test("The preview stops in the background and comes back in the foreground; recording goes on")
    func background() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let viewModel = harness.viewModel
        await viewModel.start()
        await harness.preview.emit(.finalized("Hello"))
        await waitUntil { !viewModel.preview.isEmpty }

        await viewModel.sceneDidChange(isActive: false)
        #expect(!viewModel.isPreviewOn)
        #expect(viewModel.phase == .recording)
        #expect(await harness.preview.stopCount == 1)
        #expect(viewModel.preview.isEmpty, "stale words aren't shown on return")

        await viewModel.sceneDidChange(isActive: true)
        #expect(viewModel.isPreviewOn)
        #expect(await harness.preview.startCount == 2)
        await viewModel.stop()
    }

    @Test("A hot phone stops the preview and a cool one restarts it; a hot phone at Start never opens it")
    func thermal() async throws {
        let thermal = ThermalBox()
        let harness = try makeHarness(thermal: thermal)
        defer { harness.cleanUp() }
        let viewModel = harness.viewModel
        await viewModel.start()
        #expect(viewModel.isPreviewOn)

        thermal.state = .serious
        await viewModel.thermalDidChange()
        #expect(!viewModel.isPreviewOn)
        #expect(viewModel.previewNotice == "Paused the live words to keep the iPhone cool.")
        #expect(viewModel.phase == .recording)

        thermal.state = .fair
        await viewModel.thermalDidChange()
        #expect(viewModel.isPreviewOn)
        await viewModel.stop()

        let hot = ThermalBox()
        hot.state = .critical
        let hotHarness = try makeHarness(thermal: hot)
        defer { hotHarness.cleanUp() }
        await hotHarness.viewModel.start()
        #expect(!hotHarness.viewModel.isPreviewOn)
        #expect(await hotHarness.preview.startCount == 0)
        await hotHarness.viewModel.stop()
    }

    @Test("A preview that fails to start leaves the recording untouched")
    func startFailure() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        await harness.preview.setFailsToStart(true)
        await harness.viewModel.start()
        #expect(harness.viewModel.phase == .recording)
        #expect(!harness.viewModel.isPreviewOn)
        #expect(harness.viewModel.previewNotice == "Live words aren't available right now.")
        #expect(harness.viewModel.errorMessage == nil)
        await harness.viewModel.stop()
    }
}
