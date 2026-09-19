import Foundation
import Testing
@testable import VeraFlow

@MainActor
struct AppStateTests {
    @Test("Startup loads capabilities, entitlement, and resumes the pipeline")
    func startup() async {
        var services = AppServices.fakes()
        let capabilities = FakeCapabilityService(capabilities: .noAppleIntelligence)
        let purchases = FakePurchaseService(unlocked: true, freeSummariesUsed: 2)
        let pipeline = FakePipelineCoordinator()
        services.capabilities = capabilities
        services.purchases = purchases
        services.pipeline = pipeline

        let state = AppState(services: services)
        #expect(state.capabilities == nil)
        #expect(!state.didFinishStartup)

        await state.startup()

        #expect(state.didFinishStartup)
        #expect(state.capabilities == .noAppleIntelligence)
        #expect(state.capabilities?.canSummarize == false)
        #expect(state.isUnlocked)
        #expect(state.freeSummariesUsed == 2)
        #expect(await pipeline.resumeCount == 1)
    }
}

extension AppStateTests {
    @Test("Pipeline events drive per-recording progress and clear it when the stage finishes")
    func pipelineProgress() async throws {
        var services = AppServices.fakes()
        let pipeline = FakePipelineCoordinator()
        services.pipeline = pipeline
        let state = AppState(services: services)
        await state.startup()
        let id = UUID()

        await pipeline.emit(.stageChanged(recordingID: id, stage: .transcribing))
        try await waitUntil { state.pipelineProgress[id] != nil }
        #expect(state.pipelineProgress[id] == PipelineProgress(stage: .transcribing, fraction: 0, isPreparingAssets: false))

        await pipeline.emit(.preparingAssets(recordingID: id, stage: .transcribing, fraction: 0.5))
        try await waitUntil { state.pipelineProgress[id]?.isPreparingAssets == true }

        await pipeline.emit(.progress(recordingID: id, stage: .transcribing, fraction: 0.75))
        try await waitUntil { state.pipelineProgress[id]?.fraction == 0.75 }
        #expect(state.pipelineProgress[id]?.isPreparingAssets == false)

        await pipeline.emit(.stageChanged(recordingID: id, stage: .transcribed))
        try await waitUntil { state.pipelineProgress[id] == nil }

        await pipeline.emit(.stageChanged(recordingID: id, stage: .transcribing))
        try await waitUntil { state.pipelineProgress[id] != nil }
        await pipeline.emit(.failed(recordingID: id, stage: .transcribing, message: "nope"))
        try await waitUntil { state.pipelineProgress[id] == nil }
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for the app state to update")
    }
}

extension AppStateTests {
    @Test("Stage changes and failures are kept for Diagnostics; progress ticks are not")
    func recentEvents() async throws {
        var services = AppServices.fakes()
        let pipeline = FakePipelineCoordinator()
        services.pipeline = pipeline
        let state = AppState(services: services)
        await state.startup()
        let id = UUID()

        await pipeline.emit(.stageChanged(recordingID: id, stage: .transcribing))
        await pipeline.emit(.progress(recordingID: id, stage: .transcribing, fraction: 0.5))
        await pipeline.emit(.failed(recordingID: id, stage: .transcribing, message: "x"))
        try await waitUntil { state.recentEvents.count == 2 }
        #expect(state.recentEvents.map(\.event) == [
            .stageChanged(recordingID: id, stage: .transcribing),
            .failed(recordingID: id, stage: .transcribing, message: "x"),
        ])
    }
}

extension AppStateTests {
    @Test("A summary that finishes while the app is away posts a notification with the title only; a tap opens the recording")
    func notifications() async throws {
        // The notifier reads the standard preference, which defaults to on.
        var services = AppServices.fakes()
        let pipeline = FakePipelineCoordinator()
        let notifications = FakeNotificationService()
        services.pipeline = pipeline
        services.notifications = notifications
        let container = try ModelContainerFactory.makeInMemory()
        let recording = PreviewData.sampleRecording()
        container.mainContext.insert(recording)
        try container.mainContext.save()

        let state = AppState(services: services, modelContext: container.mainContext)
        await state.startup()
        state.sceneDidChange(isActive: false)
        await pipeline.emit(.stageChanged(recordingID: recording.id, stage: .ready))
        for _ in 0..<50 where await notifications.posted.isEmpty {
            try await Task.sleep(for: .milliseconds(20))
        }
        let posted = await notifications.posted
        #expect(posted.count == 1)
        #expect(posted.first?.kind == .summaryReady)
        #expect(posted.first?.recordingTitle == "Kitchen remodel walk-through")

        // Foreground: nothing more is posted.
        state.sceneDidChange(isActive: true)
        await pipeline.emit(.failed(recordingID: recording.id, stage: .summarizing, message: "x"))
        try await Task.sleep(for: .milliseconds(50))
        #expect(await notifications.posted.count == 1)

        await notifications.simulateTap(recording.id)
        for _ in 0..<50 where state.pendingOpenRecordingID == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(state.pendingOpenRecordingID == recording.id)
        state.clearPendingOpen()
        #expect(state.pendingOpenRecordingID == nil)
    }
}
