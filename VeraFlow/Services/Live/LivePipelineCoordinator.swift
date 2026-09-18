import Foundation
import os
import SwiftData

/// Runs recordings through the processing stages one at a time, in order, persisting the stage
/// after every step so work resumes after a crash or relaunch (SPEC §6.3).
///
/// M3: recorded → transcribing → transcribed. M4: → diarizing → diarized (speaker labels;
/// failure is non-fatal). M5: → summarizing → ready (skipped, not failed, when the on-device model
/// isn't available). Each drain runs inside a background-processing task so it can finish after
/// the user leaves the app.
actor LivePipelineCoordinator: PipelineCoordinating {
    private static let log = Logger(subsystem: "com.jeremyreger.veraflow", category: "pipeline")

    private let container: ModelContainer
    private let transcription: any TranscriptionService
    private let diarization: any DiarizationService
    private let aligner: any TranscriptAligning
    private let summarization: any SummarizationService
    private let dueDates: any DueDateResolving
    private let purchases: any PurchaseService
    private let storage: RecordingStorage
    private let background: any BackgroundProcessing
    /// Reads the "Expected speakers" setting at the moment diarization starts.
    private let speakerHint: @Sendable () -> SpeakerCountHint
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
        diarization: any DiarizationService,
        aligner: any TranscriptAligning,
        summarization: any SummarizationService,
        dueDates: any DueDateResolving,
        purchases: any PurchaseService,
        storage: RecordingStorage,
        background: any BackgroundProcessing,
        speakerHint: @escaping @Sendable () -> SpeakerCountHint = { .automatic }
    ) {
        self.container = container
        self.transcription = transcription
        self.diarization = diarization
        self.aligner = aligner
        self.summarization = summarization
        self.dueDates = dueDates
        self.purchases = purchases
        self.storage = storage
        self.background = background
        self.speakerHint = speakerHint
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

    /// Stages with automatic work still ahead of them (M5: everything up to `.ready`).
    static func needsWork(_ stage: PipelineStage) -> Bool {
        switch stage {
        case .recorded, .transcribing, .transcribed, .diarizing, .diarized, .summarizing: true
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

    /// Runs every stage the recording still needs, in order, stopping at the first failure.
    private func process(_ id: UUID, progress: @Sendable @escaping (Double) -> Void) async {
        guard let recording = try? fetchRecording(id) else { return }
        if recording.stage == .recorded || recording.stage == .transcribing {
            await transcribe(recording, progress: progress)
        }
        if !Task.isCancelled, recording.stage == .transcribed || recording.stage == .diarizing {
            await diarize(recording, progress: progress)
        }
        if !Task.isCancelled, recording.stage == .diarized || recording.stage == .summarizing {
            await summarize(recording, progress: progress)
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
            handleCancellation(recording, resumeFrom: .recorded)
        } catch {
            if Task.isCancelled {
                handleCancellation(recording, resumeFrom: .recorded)
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

    /// Speaker labels (SPEC §10). Never blocks the recording: on any failure the transcript keeps
    /// one speaker, the reason is stored for a Retry banner, and the stage still becomes `.diarized`.
    private func diarize(_ recording: Recording, progress: @Sendable @escaping (Double) -> Void) async {
        let id = recording.id
        recording.stage = .diarizing
        recording.failureMessage = nil
        recording.failedStage = nil
        save()
        events.emit(.stageChanged(recordingID: id, stage: .diarizing))

        let url = storage.audioURL(for: id, fileName: recording.audioFileName)
        let hub = events
        do {
            if await !diarization.modelsReady() {
                try await diarization.prepareModels { fraction in
                    hub.emit(.preparingAssets(recordingID: id, stage: .diarizing, fraction: fraction))
                }
            }
            try Task.checkCancellation()
            let turns = try await diarization.diarize(fileURL: url, expectedSpeakers: speakerHint()) { fraction in
                hub.emit(.progress(recordingID: id, stage: .diarizing, fraction: fraction))
                progress(fraction)
            }
            try Task.checkCancellation()
            applySpeakers(turns: turns, to: recording)
            recording.stage = .diarized
            save()
            events.emit(.stageChanged(recordingID: id, stage: .diarized))
            Self.log.info("diarized \(id.uuidString, privacy: .public): \(recording.speakers.count, privacy: .public) speakers, \(recording.segments.count, privacy: .public) paragraphs")
        } catch is CancellationError {
            handleCancellation(recording, resumeFrom: .transcribed)
        } catch {
            if Task.isCancelled {
                handleCancellation(recording, resumeFrom: .transcribed)
                return
            }
            let message = PipelineFailure.message(for: error)
            applySpeakers(turns: [], to: recording)
            recording.stage = .diarized
            recording.failedStage = .diarizing
            recording.failureMessage = message
            save()
            events.emit(.failed(recordingID: id, stage: .diarizing, message: message))
            events.emit(.stageChanged(recordingID: id, stage: .diarized))
            Self.log.error("diarization failed for \(id.uuidString, privacy: .public), continuing with one speaker: \(message, privacy: .public)")
        }
    }

    /// Template summary (SPEC §11). When the on-device model isn't available the recording still
    /// becomes `.ready` (transcripts work everywhere, SPEC §15) with the reason kept for the Summary tab.
    /// A model failure is recorded the same way so the transcript stays usable; Retry re-runs it.
    private func summarize(_ recording: Recording, progress: @Sendable @escaping (Double) -> Void) async {
        let id = recording.id
        recording.stage = .summarizing
        // A non-fatal speaker-label reason stays visible; only a previous summary failure is cleared.
        if recording.failedStage == .summarizing {
            recording.failureMessage = nil
            recording.failedStage = nil
        }
        save()
        events.emit(.stageChanged(recordingID: id, stage: .summarizing))

        let hub = events
        do {
            let availability = await summarization.availability()
            guard availability.isAvailable else { throw SummarizationError.unavailable(availability) }
            guard !recording.segments.isEmpty else { throw SummarizationError.generationFailed("There is no transcript to summarize.") }
            // Free tier: 3 summaries in total, any template (SPEC §13.2). Checked here so a queued
            // 4th summary stops cleanly with the paywall reason instead of a model call.
            let unlocked = await purchases.isUnlocked()
            let freeUsed = await purchases.freeSummariesUsed()
            guard unlocked || freeUsed < FreeTier.summaryLimit else {
                throw SummarizationError.freeLimitReached
            }
            let input = SummarizationInput.make(from: recording)
            let raw = try await summarization.summarize(input) { update in
                hub.emit(.progress(recordingID: id, stage: .summarizing, fraction: update.fraction))
                progress(update.fraction)
            }
            try Task.checkCancellation()
            let processor = ActionItemPostProcessor(dueDates: dueDates)
            let payload = raw.postProcessed(with: processor, context: .init(recording: recording))
            let record = SummaryRecord(
                templateID: payload.templateID,
                payloadJSON: try payload.encoded(),
                modelInfo: "\(await summarization.modelInfo()) · prompt v\(Prompts.version)"
            )
            recording.summaries.append(record)
            recording.stage = .ready
            save()
            if !unlocked {
                await purchases.recordFreeSummaryUsed()
            }
            events.emit(.stageChanged(recordingID: id, stage: .ready))
            Self.log.info("summarized \(id.uuidString, privacy: .public) with \(payload.templateID.rawValue, privacy: .public): \(payload.actionItems.count, privacy: .public) action items")
        } catch is CancellationError {
            handleCancellation(recording, resumeFrom: .diarized)
        } catch {
            if Task.isCancelled {
                handleCancellation(recording, resumeFrom: .diarized)
                return
            }
            let message = PipelineFailure.message(for: error)
            recording.stage = .ready
            recording.failedStage = .summarizing
            recording.failureMessage = message
            save()
            events.emit(.failed(recordingID: id, stage: .summarizing, message: message))
            events.emit(.stageChanged(recordingID: id, stage: .ready))
            Self.log.error("summary skipped for \(id.uuidString, privacy: .public): \(message, privacy: .public)")
        }
    }

    /// Rebuilds the paragraphs by speaker (SPEC §10.2) unless the user has edited the transcript,
    /// in which case the existing paragraphs are only labeled so no edit is lost. No turns → one speaker.
    private func applySpeakers(turns: [SpeakerTurn], to recording: Recording) {
        let ordered = recording.orderedSegments
        let keys: [String]
        if ordered.contains(where: \.isEdited) || turns.isEmpty || ordered.contains(where: { $0.words.isEmpty }) {
            let labels = aligner.speakerKeys(forSegments: ordered.map(\.words), turns: turns)
            for (segment, label) in zip(ordered, labels) {
                segment.speakerKey = label ?? "S1"
            }
            keys = ordered.map { $0.speakerKey ?? "S1" }
        } else {
            let aligned = aligner.align(words: ordered.flatMap(\.words), turns: turns)
            for old in recording.segments {
                context.delete(old)
            }
            recording.segments = aligned.enumerated().map { index, segment in
                TranscriptSegment(
                    index: index,
                    start: segment.start,
                    end: segment.end,
                    text: segment.text,
                    speakerKey: segment.speakerKey ?? "S1",
                    words: segment.words
                )
            }
            keys = aligned.map { $0.speakerKey ?? "S1" }
        }

        // Speakers S1…Sn in order of first appearance; names the user already gave are kept.
        var seen: [String] = []
        for key in keys where !seen.contains(key) {
            seen.append(key)
        }
        if seen.isEmpty, !recording.segments.isEmpty {
            seen = ["S1"]
        }
        let existing = Dictionary(recording.speakers.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        for stale in recording.speakers where !seen.contains(stale.key) {
            context.delete(stale)
        }
        recording.speakers = seen.enumerated().map { index, key in
            existing[key] ?? Speaker(key: key, displayName: "Speaker \(index + 1)", colorIndex: index % 8)
        }
    }

    /// Deleted → leave the row alone (it is going away). Expired → back to the stage before the
    /// interrupted step so the next launch or drain picks it up again (SPEC §6.3).
    private func handleCancellation(_ recording: Recording, resumeFrom stage: PipelineStage) {
        guard !cancelledIDs.contains(recording.id) else { return }
        recording.stage = stage
        save()
        events.emit(.stageChanged(recordingID: recording.id, stage: stage))
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
        if let error = error as? SummarizationError {
            switch error {
            case .unavailable(let availability):
                switch availability {
                case .available: return "Summaries aren't available right now."
                case .deviceNotEligible: return "AI summaries need an Apple Intelligence–capable iPhone. Transcripts still work."
                case .appleIntelligenceNotEnabled: return "Turn on Apple Intelligence in Settings to get summaries."
                case .modelNotReady: return "Apple Intelligence is still downloading. Try again later."
                case .unknown(let detail): return "Summaries aren't available: \(detail)"
                }
            case .freeLimitReached: return SummarizationError.freeLimitMessage
            case .contextOverflow: return "The recording was too long to summarize in one pass."
            case .generationFailed(let detail): return "The summary couldn't be generated: \(detail)"
            case .cancelled: return "The summary was cancelled."
            }
        }
        if let error = error as? DiarizationError {
            switch error {
            case .modelsNotReady:
                return "The speaker-label models aren't downloaded yet."
            case .modelDownloadFailed(let detail):
                return "The speaker-label models couldn't be downloaded: \(detail)"
            case .processingFailed(let detail):
                return "Speaker labeling failed: \(detail)"
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
