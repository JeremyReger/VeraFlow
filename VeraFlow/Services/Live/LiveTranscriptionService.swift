import AVFAudio
import CoreMedia
import Foundation
import os
import Speech

/// On-device transcription with Apple's Speech framework (SPEC §9). `SpeechTranscriber` when the
/// device supports it, `DictationTranscriber` otherwise, and the result records which one ran.
///
/// The audio file is read and converted to the analyzer's format by hand (Apple documents that
/// the analyzer never resamples), streamed as `AnalyzerInput` buffers, and the timed words are
/// collected from the `audioTimeRange` attributes on each result. One analysis runs at a time;
/// the pipeline serializes calls, and `insufficientResources` is retried after a pause.
actor LiveTranscriptionService: TranscriptionService {
    private static let log = Logger(subsystem: "com.jeremyreger.veraflow", category: "transcription")

    /// Frames read from the file per chunk before conversion.
    private static let readChunkFrames: AVAudioFrameCount = 32_768
    private static let resourceRetryDelays: [Duration] = [.seconds(2), .seconds(5), .seconds(10)]

    private enum Module {
        case speech(SpeechTranscriber)
        case dictation(DictationTranscriber)

        var any: any SpeechModule {
            switch self {
            case .speech(let module): module
            case .dictation(let module): module
            }
        }

        var engine: TranscriptionEngine {
            switch self {
            case .speech: .speechTranscriber
            case .dictation: .dictationTranscriber
            }
        }
    }

    // MARK: TranscriptionService

    func isAvailable() async -> Bool {
        if SpeechTranscriber.isAvailable { return true }
        return await !DictationTranscriber.supportedLocales.isEmpty
    }

    func assetStatus(for locale: Locale) async -> TranscriptionAssetStatus {
        guard let (module, _) = await makeModule(for: locale) else { return .localeUnsupported }
        switch await AssetInventory.status(forModules: [module.any]) {
        case .installed: return .ready
        case .supported, .downloading: return .downloadRequired
        case .unsupported: return .localeUnsupported
        @unknown default: return .downloadRequired
        }
    }

    func prepareAssets(for locale: Locale, progress: @Sendable @escaping (Double) -> Void) async throws {
        guard let (module, _) = await makeModule(for: locale) else {
            throw TranscriptionError.localeUnsupported(locale.identifier(.bcp47))
        }
        do {
            guard let request = try await AssetInventory.assetInstallationRequest(supporting: [module.any]) else {
                progress(1)
                return
            }
            let watcher = Task {
                while !Task.isCancelled {
                    progress(min(0.99, request.progress.fractionCompleted))
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
            defer { watcher.cancel() }
            try await request.downloadAndInstall()
            progress(1)
            Self.log.info("speech assets installed for \(locale.identifier(.bcp47), privacy: .public)")
        } catch {
            throw TranscriptionError.assetDownloadFailed(error.localizedDescription)
        }
    }

    func transcribe(
        fileURL: URL,
        locale: Locale,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> TranscriptionResult {
        var attempt = 0
        while true {
            do {
                return try await transcribeOnce(fileURL: fileURL, locale: locale, progress: progress)
            } catch let error as SFSpeechError where error.code == .insufficientResources {
                guard attempt < Self.resourceRetryDelays.count else { throw TranscriptionError.insufficientResources }
                Self.log.info("insufficient resources; retrying after \(Self.resourceRetryDelays[attempt].description, privacy: .public)")
                try await Task.sleep(for: Self.resourceRetryDelays[attempt])
                attempt += 1
            }
        }
    }

    // MARK: One pass

    private func transcribeOnce(
        fileURL: URL,
        locale: Locale,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> TranscriptionResult {
        guard let (module, resolvedLocale) = await makeModule(for: locale) else {
            throw TranscriptionError.localeUnsupported(locale.identifier(.bcp47))
        }
        let modules = [module.any]
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules) else {
            throw TranscriptionError.assetDownloadFailed("The speech model isn't installed yet.")
        }
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: fileURL)
        } catch {
            throw TranscriptionError.analysisFailed("Couldn't open the audio: \(error.localizedDescription)")
        }
        let duration = file.fileFormat.sampleRate > 0 ? Double(file.length) / file.fileFormat.sampleRate : 0
        Self.log.info("transcribe: \(fileURL.lastPathComponent, privacy: .public) \(duration, format: .fixed(precision: 1), privacy: .public)s via \(module.engine.rawValue, privacy: .public) in \(resolvedLocale.identifier(.bcp47), privacy: .public); analyzer format \(analyzerFormat.sampleRate, privacy: .public) Hz \(analyzerFormat.channelCount, privacy: .public) ch")

        let analyzer = SpeechAnalyzer(modules: modules)

        // Consumer first, so no result is missed (SPEC §9.2).
        let collector: Task<[TimedWord], any Error>
        switch module {
        case .speech(let transcriber):
            collector = Task {
                try await Self.collectWords(from: transcriber.results, duration: duration, progress: progress)
            }
        case .dictation(let transcriber):
            collector = Task {
                try await Self.collectWords(from: transcriber.results, duration: duration, progress: progress)
            }
        }

        let input = Self.makeInputStream(file: file, analyzerFormat: analyzerFormat)
        do {
            if let lastTime = try await analyzer.analyzeSequence(input.stream) {
                try Task.checkCancellation()
                try await analyzer.finalizeAndFinish(through: lastTime)
            } else {
                await analyzer.cancelAndFinishNow()
            }
        } catch is CancellationError {
            input.reader.cancel()
            await analyzer.cancelAndFinishNow()
            collector.cancel()
            throw CancellationError()
        } catch let error as SFSpeechError {
            input.reader.cancel()
            collector.cancel()
            throw error
        } catch {
            input.reader.cancel()
            collector.cancel()
            throw TranscriptionError.analysisFailed(error.localizedDescription)
        }
        try Task.checkCancellation()

        let words: [TimedWord]
        do {
            words = try await collector.value
        } catch let error as SFSpeechError {
            throw error
        } catch {
            throw TranscriptionError.analysisFailed(error.localizedDescription)
        }
        progress(1)
        Self.log.info("transcribed \(words.count, privacy: .public) words")
        return TranscriptionResult(words: words, engine: module.engine, localeIdentifier: resolvedLocale.identifier(.bcp47))
    }

    /// The best module for this device and the locale it will actually use.
    private func makeModule(for locale: Locale) async -> (Module, Locale)? {
        if SpeechTranscriber.isAvailable {
            if let resolved = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
                let transcriber = SpeechTranscriber(
                    locale: resolved,
                    transcriptionOptions: [],
                    reportingOptions: [],
                    attributeOptions: [.audioTimeRange]
                )
                return (.speech(transcriber), resolved)
            }
        }
        if let resolved = await DictationTranscriber.supportedLocale(equivalentTo: locale) {
            let transcriber = DictationTranscriber(
                locale: resolved,
                contentHints: [],
                transcriptionOptions: [.punctuation],
                reportingOptions: [],
                attributeOptions: [.audioTimeRange]
            )
            return (.dictation(transcriber), resolved)
        }
        return nil
    }

    // MARK: Words

    private static func collectWords<Results: AsyncSequence>(
        from results: Results,
        duration: TimeInterval,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> [TimedWord] where Results.Element: SpeechModuleResult & TranscribedText {
        var words: [TimedWord] = []
        for try await result in results {
            words.append(contentsOf: timedWords(from: result.text))
            if duration > 0 {
                progress(min(0.99, max(0, result.resultsFinalizationTime.seconds / duration)))
            }
        }
        return words.sorted { $0.start < $1.start }
    }

    /// Reads the `audioTimeRange` attribute from each run. A run normally holds one word; a run
    /// with several words shares its range across them by character count.
    static func timedWords(from text: AttributedString) -> [TimedWord] {
        var words: [TimedWord] = []
        for run in text.runs {
            guard let range = run.audioTimeRange else { continue }
            let runText = String(text[run.range].characters)
            let tokens = runText.split(whereSeparator: \.isWhitespace).map(String.init)
            guard !tokens.isEmpty else { continue }
            let start = range.start.seconds
            let end = CMTimeAdd(range.start, range.duration).seconds
            if tokens.count == 1 {
                words.append(TimedWord(text: tokens[0], start: start, end: end))
                continue
            }
            let totalCharacters = Double(tokens.reduce(0) { $0 + $1.count })
            var cursor = start
            for token in tokens {
                let share = totalCharacters > 0 ? Double(token.count) / totalCharacters : 1 / Double(tokens.count)
                let tokenEnd = min(end, cursor + (end - start) * share)
                words.append(TimedWord(text: token, start: cursor, end: tokenEnd))
                cursor = tokenEnd
            }
        }
        return words
    }

    // MARK: Input

    /// Streams the file as analyzer-format buffers from a background task. Contiguous buffers
    /// with no explicit start time, so the analyzer's time-codes follow the file.
    private static func makeInputStream(
        file: AVAudioFile,
        analyzerFormat: AVAudioFormat
    ) -> (stream: AsyncStream<AnalyzerInput>, reader: Task<Void, Never>) {
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        let box = FileBox(file: file)
        let reader = Task.detached(priority: .userInitiated) {
            defer { continuation.finish() }
            let readFormat = box.file.processingFormat
            guard let converter = AVAudioConverter(from: readFormat, to: analyzerFormat) else {
                log.error("no converter from \(readFormat.description, privacy: .public) to the analyzer format")
                return
            }
            let resampler = BufferResampler(converter: converter, outputFormat: analyzerFormat)
            while !Task.isCancelled {
                guard let chunk = AVAudioPCMBuffer(pcmFormat: readFormat, frameCapacity: readChunkFrames) else { return }
                do {
                    try box.file.read(into: chunk, frameCount: readChunkFrames)
                } catch {
                    log.error("read failed: \(error.localizedDescription, privacy: .public)")
                    return
                }
                if chunk.frameLength == 0 { break }
                if let converted = resampler.convert(chunk) {
                    continuation.yield(AnalyzerInput(buffer: converted))
                }
            }
            if !Task.isCancelled, let tail = resampler.flush() {
                continuation.yield(AnalyzerInput(buffer: tail))
            }
        }
        return (stream, reader)
    }

    /// `AVAudioFile` isn't Sendable; the reader task is its only user after creation.
    private final class FileBox: @unchecked Sendable {
        let file: AVAudioFile
        init(file: AVAudioFile) { self.file = file }
    }
}

/// Both transcriber result types expose their text this way; lets one collector serve both.
protocol TranscribedText {
    var text: AttributedString { get }
}

extension SpeechTranscriber.Result: TranscribedText {}
extension DictationTranscriber.Result: TranscribedText {}
