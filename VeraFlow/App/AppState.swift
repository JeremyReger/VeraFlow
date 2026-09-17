import Foundation
import Observation
import SwiftData

/// App-wide state the UI reads: device capabilities, the unlock entitlement, and launch recovery.
@Observable
@MainActor
final class AppState {
    private(set) var capabilities: Capabilities?
    private(set) var isUnlocked = false
    private(set) var freeSummariesUsed = 0
    private(set) var didFinishStartup = false
    /// Set when launch found an interrupted recording (SPEC §8.2); shown once as an alert.
    private(set) var recoveryMessage: String?
    private(set) var lastRecovery: RecordingRecoveryOutcome?

    private let services: AppServices
    private let modelContext: ModelContext?
    private var entitlementTask: Task<Void, Never>?

    /// `modelContext` enables crash recovery of interrupted recordings; pass `nil` to skip it.
    init(services: AppServices, modelContext: ModelContext? = nil) {
        self.services = services
        self.modelContext = modelContext
    }

    /// Runs the launch checks: capabilities, entitlement, and pipeline recovery (SPEC §4.1, §6.3, §8.2).
    func startup() async {
        capabilities = await services.capabilities.refresh()
        isUnlocked = await services.purchases.isUnlocked()
        freeSummariesUsed = await services.purchases.freeSummariesUsed()
        recoverInterruptedRecordings()
        await services.pipeline.resumePendingWork()
        didFinishStartup = true
        observeEntitlement()
    }

    func dismissRecoveryMessage() {
        recoveryMessage = nil
    }

    private func recoverInterruptedRecordings() {
        guard let modelContext else { return }
        let recovery = RecordingRecovery(context: modelContext, storage: services.storage)
        do {
            let outcome = try recovery.run()
            lastRecovery = outcome
            recoveryMessage = outcome.userMessage
        } catch {
            recoveryMessage = "Couldn't check for interrupted recordings: \(error.localizedDescription)"
        }
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
