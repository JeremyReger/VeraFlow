import Foundation

/// A local notification about one recording's processing (v1.1 plan item 6). The body is the
/// recording's title only: no transcript or summary text ever reaches the Lock Screen.
struct ProcessingNotification: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Transcript, labels and summary are done.
        case summaryReady
        /// A stage stopped and needs the user (a failure, the free limit, a model that isn't available).
        case needsAttention
    }

    var kind: Kind
    var recordingID: UUID
    var recordingTitle: String

    var title: String {
        switch kind {
        case .summaryReady: "Summary ready"
        case .needsAttention: "Needs attention"
        }
    }

    /// One identifier per recording, so a later notification replaces an earlier one.
    var identifier: String { "processing.\(recordingID.uuidString)" }
}

/// Decides which pipeline events become notifications. Stateful because the pipeline reports a
/// summary failure as `.failed` followed by `.stageChanged(.ready)`, and that "ready" is not a
/// summary. Pure and unit-tested.
struct ProcessingNotifier: Equatable, Sendable {
    /// Recordings whose last run failed, so the `.ready` that follows (and any repeat of it) is
    /// not announced until a new run starts.
    private var failedIDs: Set<UUID> = []
    /// Recordings already announced as ready, so a relabel or retry doesn't announce twice.
    private var announcedReadyIDs: Set<UUID> = []

    init() {}

    /// The notification kind for `event`, or `nil`. Nothing is announced while the app is in the
    /// foreground or when the user turned notifications off in Settings.
    mutating func decide(_ event: PipelineEvent, appIsActive: Bool, enabled: Bool) -> (kind: ProcessingNotification.Kind, recordingID: UUID)? {
        switch event {
        case .failed(let id, let stage, _):
            // Speaker labels failing is non-fatal (SPEC §6.3): processing continues to the summary.
            guard stage != .diarizing else { return nil }
            failedIDs.insert(id)
            announcedReadyIDs.remove(id)
            guard !appIsActive, enabled else { return nil }
            return (.needsAttention, id)
        case .stageChanged(let id, let stage):
            switch stage {
            case .ready:
                guard !failedIDs.contains(id), !announcedReadyIDs.contains(id) else { return nil }
                announcedReadyIDs.insert(id)
                guard !appIsActive, enabled else { return nil }
                return (.summaryReady, id)
            case .recorded, .transcribing, .diarizing, .summarizing:
                // A fresh run (retry, re-transcribe): it may be announced again when it finishes.
                announcedReadyIDs.remove(id)
                failedIDs.remove(id)
                return nil
            default:
                return nil
            }
        case .progress, .preparingAssets, .recoveredInterruptedRecording:
            return nil
        }
    }
}

/// Local notifications only; nothing leaves the phone. `LiveNotificationService` is the real one.
protocol NotificationService: Sendable {
    /// Quiet (provisional) delivery to Notification Center with no permission prompt. Idempotent.
    func requestProvisionalAuthorization() async
    /// The full prompt, from the Settings toggle. Returns whether alerts are allowed now.
    func requestAuthorization() async -> Bool
    func post(_ notification: ProcessingNotification) async
    /// Removes delivered and pending notifications for a recording (it was opened or deleted).
    func clear(recordingID: UUID) async
    /// Recording IDs from notifications the user tapped, including the one that launched the app.
    func taps() async -> AsyncStream<UUID>
}

actor FakeNotificationService: NotificationService {
    private(set) var provisionalRequests = 0
    private(set) var authorizationRequests = 0
    private(set) var posted: [ProcessingNotification] = []
    private(set) var cleared: [UUID] = []
    var authorizationResult = true
    private var continuations: [UUID: AsyncStream<UUID>.Continuation] = [:]

    func requestProvisionalAuthorization() async { provisionalRequests += 1 }

    func requestAuthorization() async -> Bool {
        authorizationRequests += 1
        return authorizationResult
    }

    func post(_ notification: ProcessingNotification) async { posted.append(notification) }

    func clear(recordingID: UUID) async { cleared.append(recordingID) }

    func taps() async -> AsyncStream<UUID> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<UUID>.makeStream()
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.remove(id) }
        }
        return stream
    }

    /// Test control: the user tapped a notification for this recording.
    func simulateTap(_ recordingID: UUID) {
        for continuation in continuations.values {
            continuation.yield(recordingID)
        }
    }

    func setAuthorizationResult(_ value: Bool) { authorizationResult = value }

    private func remove(_ id: UUID) { continuations[id] = nil }
}
