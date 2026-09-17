import Foundation
import os
import SwiftData

/// Runs recordings through the processing stages one at a time, in order, persisting the stage
/// after every step so work resumes after a crash or relaunch (SPEC §6.3).
///
/// M3: recorded → transcribing → transcribed. M4 and M5 add diarization and summarization
/// behind the same queue. Each drain runs inside a background-processing task so it can
/// finish after the user leaves the app.
actor LivePipelineCoordinator: PipelineCoordinating {
    private static let log = Logger(subsystem: "com.jeremyreger.veraflow", category: "pipeline")

    private let container: ModelContainer
    private let transcription: any TranscriptionService
    private let storage: RecordingStorage
    private let background: any BackgroundProcessing
    private let events = PipelineEventHub()

    private lazy var context = ModelContext(container)
    private var queue: [UUID] = []
    private var current: UUID?
    private var currentTask: Task<Void, Never>?
    private var drainTask: Task<Void, Never>?
    /// Recordings whose processing was cancelled because they were deleted; never touch them again.
    private var cancelledIDs: Set<UUID> = []

    init(
        container: ModelContainer,
        transcription: any TranscriptionService,
        storage: RecordingStorage,
        background: any BackgroundProcessing
    ) {
        self.container = container
        self.transcription = transcription
        self.storage = storage
        self.background = background
    }

    // MARK: PipelineCoordinating

    func enqueue(recordingID: UUID) async {
        cancelledIDs.remove(recordingID)
        guard current != recordingID, !queue.contains(recordingID) else { return }
        queue.append(recordingID)
        startDrainIfNeeded()
    }

    func retry(recordingID: UUID, from stage: PipelineStage) async {
        guard let recording = try? fetchRecording(recordingID) else { return }
        recording.stage = Self.stageBefore(stage)
        recording.failureMessage = nil
        recording.failedStage = nil
        try? context.save()
        await enqueue(recordingID: recordingID)
    }

    func resumePendingWork() async {
        let pending = ((try? context.fetch(FetchDescriptor<Recording>())) ?? [])
            .filter { Self.needsWork($0.stage) }
            .sorted { $0.createdAt < $1.createdAt }
        for recording in pending {
            await enqueue(recordingID: recording.id)
        }
    }

    func cancel(recordingID: UUID) async {
        queue.removeAll { $0 == recordingID }
        if current == recordingID {
            cancelledIDs.insert(recordingID)
            currentTask?.cancel()
        }
    }

    func events() async -> AsyncStream<PipelineEvent> {
        events.makeStream()
    }

    // MARK: Queue

    /// Stages with automatic work still ahead of them (M3: up to transcription).
    static func needsWork(_ stage: PipelineStage) -> Bool {
        switch stage {
        case .recorded, .transcribing: true
        default: false
        }
    }

    /// The stage a recording returns to so that `stage` runs again.
    static func stageBefore(_ stage: PipelineStage) -> PipelineStage {
        switch stage {
        case .transcribing, .transcribed: .recorded
        case .diarizing, .diarized: .transcribed
        case .summarizing, .ready: .diarized
        case .recording, .recorded, .failed: .recorded
        }
    }

    private func startDrainIfNeeded() {
        guard drainTask == nil else { return }
        drainTask = Task { [weak self] in
            guard let self else { return }
            await self.background.run(title: "Processing recordings") { progress in
                await self.drain(progress: progress)
            }
            await self.finishDrain()
        }
    }

    private func finishDrain() {
        drainTask = nil
        if !queue.isEmpty {
            startDrainIfNeeded()
        }
    }

    private func drain(progress: @Sendable @escaping (Double) -> Void) async {
        while !Task.isCancelled, !queue.isEmpty {
            let id = queue.removeFirst()
            current = id
            let task = Task { await self.process(id, progress: progress) }
            currentTask = task
            await task.value
            currentTask = nil
            current = nil
        }
    }

    // MARK: Steps

    private func process(_ id: UUID, progress: @Sendable @escaping (Double) -> Void) async {
        guard let recording = try? fetchRecording(id) else { return }
        switch recording.stage {
        case .recorded, .transcribing:
            await transcribe(recording, progress: progress)
        default:
            return
        }
    }

    private func transcribe(_ recording: Recording, progress: @Sendable @escaping (Double) -> Void) async {
        let id = recording.id
        recording.stage = .transcribing
        recording.failureMessage = nil
        recording.failedStage = nil
        save()
        events.emit(.stageChanged(recordingID: id, stage: .transcribing))

        let locale = Locale(identifier: recording.localeIdentifier)
        let url = storage.audioURL(for: id, fileName: recording.audioFileName)
        let hub = events
        do {
            guard await transcription.isAvailable() else { throw TranscriptionError.unavailable }
            if await transcription.assetStatus(for: locale) == .downloadRequired {
                try await transcription.prepareAssets(for: locale) { fraction in
                    hub.emit(.preparingAssets(recordingID: id, stage: .transcribing, fraction: fraction))
                }
            }
            try Task.checkCancellation()
            let result = try await transcription.transcribe(fileURL: url, locale: locale) { fraction in
                hub.emit(.progress(recordingID: id, stage: .transcribing, fraction: fraction))
                progress(fraction)
            }
            try Task.checkCancellation()

            for old in recording.segments {
                context.delete(old)
            }
            recording.segments = Paragrapher.segments(from: result.words).enumerated().map { index, segment in
                TranscriptSegment(index: index, start: segment.start, end: segment.end, text: segment.text, words: segment.words)
            }
            recording.transcriptionEngine = result.engine
            recording.localeIdentifier = result.localeIdentifier
            recording.stage = .transcribed
            save()
            events.emit(.stageChanged(recordingID: id, stage: .transcribed))
            Self.log.info("transcribed \(id.uuidString, privacy: .public): \(result.words.count, privacy: .public) words, \(recording.segments.count, privacy: .public) paragraphs, engine \(result.engine.rawValue, privacy: .public)")
        } catch is CancellationError {
            handleCancellation(recording)
        } catch {
            if Task.isCancelled {
                handleCancellation(recording)
                return
            }
            let message = PipelineFailure.message(for: error)
            recording.stage = .failed
            recording.failedStage = .transcribing
            recording.failureMessage = message
            save()
            events.emit(.failed(recordingID: id, stage: .transcribing, message: message))
            Self.log.error("transcription failed for \(id.uuidString, privacy: .public): \(message, privacy: .public)")
        }
    }

    /// Deleted → leave the row alone (it is going away). Expired → back to `.recorded` so the next
    /// launch or drain picks it up again (SPEC §6.3).
    private func handleCancellation(_ recording: Recording) {
        guard !cancelledIDs.contains(recording.id) else { return }
        recording.stage = .recorded
        save()
        events.emit(.stageChanged(recordingID: recording.id, stage: .recorded))
        if !queue.contains(recording.id) {
            queue.append(recording.id)
        }
    }

    // MARK: Persistence

    private func fetchRecording(_ id: UUID) throws -> Recording? {
        var descriptor = FetchDescriptor<Recording>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func save() {
        do {
            try context.save()
        } catch {
            Self.log.error("save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// User-facing text for a stage failure.
enum PipelineFailure {
    static func message(for error: Error) -> String {
        if let error = error as? TranscriptionError {
            switch error {
            case .unavailable:
                return "Transcription isn't available on this iPhone."
            case .localeUnsupported(let identifier):
                return "Transcription doesn't support \(identifier) yet."
            case .assetDownloadFailed(let detail):
                return "The speech model couldn't be downloaded: \(detail)"
            case .insufficientResources:
                return "The iPhone was too busy to transcribe. Tap Retry to try again."
            case .analysisFailed(let detail):
                return "Transcription failed: \(detail)"
            }
        }
        return error.localizedDescription
    }
}

/// Fan-out for pipeline events that can be called from any thread (progress callbacks included).
final class PipelineEventHub: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<PipelineEvent>.Continuation] = [:]

    func makeStream() -> AsyncStream<PipelineEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<PipelineEvent>.makeStream()
        lock.withLock { continuations[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            self?.lock.withLock { self?.continuations[id] = nil }
        }
        return stream
    }

    func emit(_ event: PipelineEvent) {
        let targets = lock.withLock { Array(continuations.values) }
        for continuation in targets {
            continuation.yield(event)
        }
    }
}
