import Foundation

/// Which speech engine produced a transcript (SPEC §9.1, §15).
enum TranscriptionEngine: String, Codable, Sendable {
    /// `SpeechTranscriber`: full quality.
    case speechTranscriber
    /// `DictationTranscriber`: fallback on older devices; UI shows a "Standard accuracy" badge.
    case dictationTranscriber
    /// FluidAudio Parakeet, benchmark only in v1 (SPEC §9.4).
    case parakeet
    case fake
}

struct TranscriptionResult: Sendable, Equatable {
    var words: [TimedWord]
    var engine: TranscriptionEngine
    var localeIdentifier: String
}

/// Readiness of the speech assets for a locale (SPEC §9.1).
enum TranscriptionAssetStatus: Sendable, Equatable {
    case ready
    case downloadRequired
    case localeUnsupported
}

enum TranscriptionError: Error, Equatable {
    case unavailable
    case localeUnsupported(String)
    case assetDownloadFailed(String)
    case insufficientResources
    case analysisFailed(String)
}

/// Transcribes an audio file on device (SPEC §9). Implemented for real in M3.
protocol TranscriptionService: Sendable {
    /// Whether any on-device transcriber is available on this device.
    func isAvailable() async -> Bool
    /// Every locale this engine can transcribe on this device (v1.1 plan item 8: the language picker).
    func supportedLocales() async -> [Locale]
    /// Checks whether assets for `locale` are installed.
    func assetStatus(for locale: Locale) async -> TranscriptionAssetStatus
    /// Downloads assets for `locale` if needed, reporting 0...1 progress. Idempotent.
    func prepareAssets(for locale: Locale, progress: @Sendable @escaping (Double) -> Void) async throws
    /// Transcribes the whole file. `progress` is 0...1 based on finalized audio time / duration.
    func transcribe(
        fileURL: URL,
        locale: Locale,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> TranscriptionResult
}

/// Returns canned words instantly.
actor FakeTranscriptionService: TranscriptionService {
    var available = true
    var assetStatusToReport: TranscriptionAssetStatus = .ready
    var wordsToReturn: [TimedWord]
    var errorToThrow: TranscriptionError?
    var locales: [Locale] = [Locale(identifier: "en_US"), Locale(identifier: "es_ES"), Locale(identifier: "fr_FR")]
    /// Test control: how long `transcribe` pretends to work (honours cancellation).
    var delay: Duration = .zero
    private(set) var transcribedURLs: [URL] = []
    private(set) var prepareCount = 0

    init(words: [TimedWord] = FakeTranscriptionService.sampleWords) {
        self.wordsToReturn = words
    }

    func isAvailable() async -> Bool { available }

    func supportedLocales() async -> [Locale] { locales }

    func assetStatus(for locale: Locale) async -> TranscriptionAssetStatus { assetStatusToReport }

    func prepareAssets(for locale: Locale, progress: @Sendable @escaping (Double) -> Void) async throws {
        prepareCount += 1
        progress(0.5)
        progress(1)
        assetStatusToReport = .ready
    }

    func transcribe(
        fileURL: URL,
        locale: Locale,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> TranscriptionResult {
        if let errorToThrow { throw errorToThrow }
        transcribedURLs.append(fileURL)
        progress(0.5)
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        progress(1)
        return TranscriptionResult(
            words: wordsToReturn,
            engine: .fake,
            localeIdentifier: locale.identifier(.bcp47)
        )
    }

    // MARK: Test controls

    func setError(_ error: TranscriptionError?) { errorToThrow = error }
    func setAssetStatus(_ status: TranscriptionAssetStatus) { assetStatusToReport = status }
    func setAvailable(_ available: Bool) { self.available = available }
    func setDelay(_ delay: Duration) { self.delay = delay }
    func setLocales(_ locales: [Locale]) { self.locales = locales }

    /// A short two-sentence exchange, ~6 seconds long.
    static let sampleWords: [TimedWord] = {
        let text = "We need the permit before we pour the footer. I will call the county on Monday."
        var time: TimeInterval = 0
        return text.split(separator: " ").map { word in
            defer { time += 0.4 }
            return TimedWord(text: String(word), start: time, end: time + 0.35)
        }
    }()
}
