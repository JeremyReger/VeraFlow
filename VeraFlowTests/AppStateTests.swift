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
