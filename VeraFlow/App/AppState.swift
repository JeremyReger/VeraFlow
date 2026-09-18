import Foundation
import Observation
import SwiftData

/// Live progress of one recording's processing, for banners and rows (SPEC §4.3).
struct PipelineProgress: Equatable, Sendable {
    var stage: PipelineStage
    /// 0...1 within the stage.
    var fraction: Double
    /// A one-time model download is running before the stage proper.
    var isPreparingAssets: Bool
}

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
    /// Audio files handed to the app via the share sheet / "Open in", waiting for the Library to import them.
    private(set) var pendingImportURLs: [URL] = []
    /// Processing progress by recording id; absent when nothing is running for it.
    private(set) var pipelineProgress: [UUID: PipelineProgress] = [:]
    /// The last pipeline events with their arrival time, for the Diagnostics screen (SPEC §15).
    private(set) var recentEvents: [PipelineTimeline.Entry] = []
    static let recentEventLimit = 200

    private let services: AppServices
    private let modelContext: ModelContext?
    private var entitlementTask: Task<Void, Never>?
    private var pipelineTask: Task<Void, Never>?

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
        await observePipeline()
        await services.pipeline.resumePendingWork()
        didFinishStartup = true
        observeEntitlement()
    }

    /// Feeds `pipelineProgress` from the coordinator's events. The subscription is made before
    /// this returns, so nothing emitted by `resumePendingWork()` is missed.
    private func observePipeline() async {
        pipelineTask?.cancel()
        let events = await services.pipeline.events()
        pipelineTask = Task {
            for await event in events {
                self.apply(event)
            }
        }
    }

    private func apply(_ event: PipelineEvent) {
        if case .progress = event {
            // Progress ticks are too many to keep; stage changes, downloads, and failures are enough.
        } else {
            recentEvents.append(PipelineTimeline.Entry(date: .now, event: event))
            if recentEvents.count > Self.recentEventLimit {
                recentEvents.removeFirst(recentEvents.count - Self.recentEventLimit)
            }
        }
        switch event {
        case .stageChanged(let id, let stage):
            if stage.isProcessing {
                pipelineProgress[id] = PipelineProgress(stage: stage, fraction: 0, isPreparingAssets: false)
            } else {
                pipelineProgress[id] = nil
            }
        case .progress(let id, let stage, let fraction):
            pipelineProgress[id] = PipelineProgress(stage: stage, fraction: fraction, isPreparingAssets: false)
        case .preparingAssets(let id, let stage, let fraction):
            pipelineProgress[id] = PipelineProgress(stage: stage, fraction: fraction, isPreparingAssets: true)
        case .failed(let id, _, _), .recoveredInterruptedRecording(let id):
            pipelineProgress[id] = nil
        }
    }

    func dismissRecoveryMessage() {
        recoveryMessage = nil
    }

    /// Queues a file from `onOpenURL`. Only file URLs are accepted.
    func enqueueImport(_ url: URL) {
        guard url.isFileURL else { return }
        pendingImportURLs.append(url)
    }

    /// Hands the queued files to whoever will import them and clears the queue.
    func takePendingImports() -> [URL] {
        defer { pendingImportURLs = [] }
        return pendingImportURLs
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
