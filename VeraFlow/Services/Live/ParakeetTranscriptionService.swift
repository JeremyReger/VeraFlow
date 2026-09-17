import Foundation
import FluidAudio
import os

/// FluidAudio's Parakeet TDT v3 speech-to-text on Core ML (SPEC §9.4). Benchmark engine in v1:
/// the Settings → Benchmark screen (debug builds) runs it next to Apple's engine on the same file.
/// Fully on device; the models download once from Hugging Face (SPEC §14.1).
actor ParakeetTranscriptionService: TranscriptionService {
    private static let log = Logger(subsystem: "com.jeremyreger.veraflow", category: "parakeet")
    private static let version: AsrModelVersion = .v3

    private var models: AsrModels?

    func isAvailable() async -> Bool {
        // Core ML models run on every iPhone we support; the language check is per call.
        true
    }

    func assetStatus(for locale: Locale) async -> TranscriptionAssetStatus {
        guard Self.language(for: locale) != nil else { return .localeUnsupported }
        if models != nil { return .ready }
        let directory = AsrModels.defaultCacheDirectory(for: Self.version)
        return AsrModels.modelsExist(at: directory, version: Self.version) ? .ready : .downloadRequired
    }

    func prepareAssets(for locale: Locale, progress: @Sendable @escaping (Double) -> Void) async throws {
        guard Self.language(for: locale) != nil else {
            throw TranscriptionError.localeUnsupported(locale.identifier(.bcp47))
        }
        do {
            models = try await AsrModels.downloadAndLoad(version: Self.version) { update in
                progress(update.fractionCompleted)
            }
            progress(1)
        } catch {
            throw TranscriptionError.assetDownloadFailed(error.localizedDescription)
        }
    }

    func transcribe(
        fileURL: URL,
        locale: Locale,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> TranscriptionResult {
        guard let language = Self.language(for: locale) else {
            throw TranscriptionError.localeUnsupported(locale.identifier(.bcp47))
        }
        let models = try await loadedModels()
        let manager = AsrManager(config: .default)
        do {
            try await manager.loadModels(models)
        } catch {
            throw TranscriptionError.analysisFailed("Couldn't load the Parakeet model: \(error.localizedDescription)")
        }
        defer { Task { await manager.cleanup() } }

        let watcher = Task {
            for try await fraction in await manager.transcriptionProgressStream {
                progress(min(0.99, fraction))
            }
        }
        defer { watcher.cancel() }

        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let result: ASRResult
        do {
            result = try await manager.transcribe(fileURL, decoderState: &state, language: language)
        } catch {
            throw TranscriptionError.analysisFailed(error.localizedDescription)
        }
        try Task.checkCancellation()

        let words = buildWordTimings(from: result.tokenTimings ?? []).map {
            TimedWord(text: $0.word, start: $0.startTime, end: $0.endTime)
        }
        progress(1)
        Self.log.info("parakeet: \(words.count, privacy: .public) words in \(result.processingTime, format: .fixed(precision: 1), privacy: .public)s (\(result.rtfx, format: .fixed(precision: 1), privacy: .public)x real time)")
        return TranscriptionResult(words: words, engine: .parakeet, localeIdentifier: locale.identifier(.bcp47))
    }

    private func loadedModels() async throws -> AsrModels {
        if let models { return models }
        do {
            let loaded = try await AsrModels.loadFromCache(version: Self.version)
            models = loaded
            return loaded
        } catch {
            throw TranscriptionError.assetDownloadFailed("The Parakeet model isn't downloaded yet.")
        }
    }

    /// Parakeet v3 covers 25 European languages, keyed by ISO language code.
    static func language(for locale: Locale) -> Language? {
        guard let code = locale.language.languageCode?.identifier else { return nil }
        return Language(rawValue: code)
    }
}
