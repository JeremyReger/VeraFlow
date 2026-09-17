import Foundation
import Observation

/// App-wide state the UI reads: device capabilities and the unlock entitlement.
@Observable
@MainActor
final class AppState {
    private(set) var capabilities: Capabilities?
    private(set) var isUnlocked = false
    private(set) var freeSummariesUsed = 0
    private(set) var didFinishStartup = false

    private let services: AppServices
    private var entitlementTask: Task<Void, Never>?

    init(services: AppServices) {
        self.services = services
    }

    /// Runs the launch checks: capabilities, entitlement, and pipeline recovery (SPEC §4.1, §6.3, §8.2).
    func startup() async {
        capabilities = await services.capabilities.refresh()
        isUnlocked = await services.purchases.isUnlocked()
        freeSummariesUsed = await services.purchases.freeSummariesUsed()
        await services.pipeline.resumePendingWork()
        didFinishStartup = true
        observeEntitlement()
    }

    /// Re-reads capabilities, e.g. after returning from Settings.
    func refreshCapabilities() async {
        capabilities = await services.capabilities.refresh()
    }

    private func observeEntitlement() {
        entitlementTask?.cancel()
        entitlementTask = Task { [services] in
            for await unlocked in await services.purchases.entitlementUpdates() {
                self.isUnlocked = unlocked
            }
        }
    }
}
