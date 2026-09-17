import Foundation

/// Something the pipeline wants the UI to know.
enum PipelineEvent: Sendable, Equatable {
    case stageChanged(recordingID: UUID, stage: PipelineStage)
    case progress(recordingID: UUID, stage: PipelineStage, fraction: Double)
    case failed(recordingID: UUID, stage: PipelineStage, message: String)
    /// A recording was found with `stage == .recording` on launch and repaired (SPEC §8.2).
    case recoveredInterruptedRecording(recordingID: UUID)
}

/// Runs recordings through transcribe → diarize → summarize, one at a time, resumably (SPEC §6.3).
/// Implemented for real across M3–M5; the background task wrapper lands in M3.
protocol PipelineCoordinating: Sendable {
    /// Queues a recording for processing from its current stage.
    func enqueue(recordingID: UUID) async
    /// Re-runs a failed or skipped stage.
    func retry(recordingID: UUID, from stage: PipelineStage) async
    /// Called on launch: repairs interrupted recordings and resumes queued work.
    func resumePendingWork() async
    /// Cancels work for a recording (e.g. it was deleted).
    func cancel(recordingID: UUID) async
    func events() async -> AsyncStream<PipelineEvent>
}

/// Records what it was asked to do and lets tests emit events by hand.
actor FakePipelineCoordinator: PipelineCoordinating {
    private(set) var enqueued: [UUID] = []
    private(set) var retries: [(id: UUID, stage: PipelineStage)] = []
    private(set) var cancelled: [UUID] = []
    private(set) var resumeCount = 0
    private var continuations: [UUID: AsyncStream<PipelineEvent>.Continuation] = [:]

    func enqueue(recordingID: UUID) async {
        enqueued.append(recordingID)
    }

    func retry(recordingID: UUID, from stage: PipelineStage) async {
        retries.append((recordingID, stage))
    }

    func resumePendingWork() async {
        resumeCount += 1
    }

    func cancel(recordingID: UUID) async {
        cancelled.append(recordingID)
    }

    func events() async -> AsyncStream<PipelineEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<PipelineEvent>.makeStream()
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.remove(id) }
        }
        return stream
    }

    /// Test control: pushes an event to every listener.
    func emit(_ event: PipelineEvent) {
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    private func remove(_ id: UUID) {
        continuations[id] = nil
    }
}
