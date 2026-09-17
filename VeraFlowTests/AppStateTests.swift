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
