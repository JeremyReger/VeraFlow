import AVFAudio
import Foundation
import os
import Speech

/// Words while recording (v1.1 plan item 4): its own `SpeechAnalyzer` fed from the recorder's
/// tap, reporting volatile results. Runs only with `SpeechTranscriber` (never the dictation
/// fallback), and only while the app is in the foreground and the phone isn't hot; the view
/// model enforces those. Nothing is stored; the file pass after Stop makes the real transcript.
///
/// Verify against the SDK: `SpeechTranscriber(locale:transcriptionOptions:reportingOptions:attributeOptions:)`
/// with `.volatileResults`, `SpeechAnalyzer.start(inputSequence:)`, `cancelAndFinishNow()`,
/// `SpeechTranscriber.Result.isFinal`, and whether a second analyzer may hold the same locale
/// while the file pass runs later (it never runs at the same time here).
@available(iOS 26, *)
actor LiveTranscriptPreview: TranscriptPreviewService {
    private static let log = Logger(subsystem: "com.jeremyreger.veraflow", category: "preview")

    private var analyzer: SpeechAnalyzer?
    private var feeder: PreviewFeeder?
    private var resultsTask: Task<Void, Never>?

    func isAvailable(locale: Locale) async -> Bool {
        guard SpeechTranscriber.isAvailable else { return false }
        return await SpeechTranscriber.supportedLocale(equivalentTo: locale) != nil
    }

    func start(locale: Locale) async throws -> PreviewSession {
        await stop()
        guard SpeechTranscriber.isAvailable,
              let resolved = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw TranscriptPreviewError.unavailable
        }
        let transcriber = SpeechTranscriber(
            locale: resolved,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw TranscriptPreviewError.unavailable
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let (input, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()
        let (events, eventContinuation) = AsyncStream<PreviewEvent>.makeStream()

        // Consumer first, so no result is missed (same rule as the file pass).
        resultsTask = Task {
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    eventContinuation.yield(result.isFinal ? .finalized(text) : .volatile(text))
                }
            } catch {
                Self.log.info("preview results ended: \(error.localizedDescription, privacy: .public)")
            }
            eventContinuation.finish()
        }
        do {
            try await analyzer.start(inputSequence: input)
        } catch {
            resultsTask?.cancel()
            resultsTask = nil
            inputContinuation.finish()
            throw TranscriptPreviewError.failed(error.localizedDescription)
        }
        let feeder = PreviewFeeder(targetFormat: format, continuation: inputContinuation)
        self.analyzer = analyzer
        self.feeder = feeder
        Self.log.info("preview started in \(resolved.identifier(.bcp47), privacy: .public); analyzer format \(format.sampleRate, privacy: .public) Hz")
        return PreviewSession(events: events) { buffer in
            feeder.feed(buffer)
        }
    }

    func stop() async {
        guard let analyzer else { return }
        feeder?.close()
        feeder = nil
        self.analyzer = nil
        await analyzer.cancelAndFinishNow()
        resultsTask?.cancel()
        resultsTask = nil
    }
}

/// Converts tap buffers to the analyzer's format and yields them. Called on the render
/// thread; the converter is built from the first buffer's format and guarded by a lock.
@available(iOS 26, *)
private final class PreviewFeeder: @unchecked Sendable {
    private let targetFormat: AVAudioFormat
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private let lock = NSLock()
    private var resampler: BufferResampler?
    private var isClosed = false

    init(targetFormat: AVAudioFormat, continuation: AsyncStream<AnalyzerInput>.Continuation) {
        self.targetFormat = targetFormat
        self.continuation = continuation
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed else { return }
        if resampler == nil {
            guard let converter = AVAudioConverter(from: buffer.format, to: targetFormat) else { return }
            resampler = BufferResampler(converter: converter, outputFormat: targetFormat)
        }
        if let converted = resampler?.convert(buffer) {
            continuation.yield(AnalyzerInput(buffer: converted))
        }
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed else { return }
        isClosed = true
        continuation.finish()
    }
}
