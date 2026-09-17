import Foundation

/// A stretch of audio attributed to one speaker, as returned by the diarizer.
struct SpeakerTurn: Sendable, Equatable {
    /// Diarizer's own speaker ID (e.g. FluidAudio's). Mapped to "S1…Sn" by the aligner.
    var speakerID: String
    var start: TimeInterval
    var end: TimeInterval
}

enum DiarizationError: Error, Equatable {
    case modelsNotReady
    case modelDownloadFailed(String)
    case processingFailed(String)
}

/// Speaker diarization on device via FluidAudio (SPEC §10). `LiveDiarizationService` is the real one.
/// Failure is non-fatal: the pipeline continues with a single speaker (SPEC §6.3).
protocol DiarizationService: Sendable {
    /// Whether the Core ML models are installed.
    func modelsReady() async -> Bool
    /// Downloads/loads models if needed, reporting 0...1 progress. One-time.
    func prepareModels(progress: @Sendable @escaping (Double) -> Void) async throws
    /// Returns speaker turns for the file, sorted by start. `expectedSpeakers` is a hint from
    /// Settings (SPEC §10.3). An empty result means one speaker. `progress` is 0...1.
    func diarize(
        fileURL: URL,
        expectedSpeakers: SpeakerCountHint,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> [SpeakerTurn]
}

/// Returns scripted turns.
actor FakeDiarizationService: DiarizationService {
    var ready = true
    var turnsToReturn: [SpeakerTurn]
    var errorToThrow: DiarizationError?
    private(set) var prepareCount = 0
    private(set) var diarizedURLs: [URL] = []
    private(set) var hints: [SpeakerCountHint] = []

    init(turns: [SpeakerTurn] = FakeDiarizationService.sampleTurns) {
        self.turnsToReturn = turns
    }

    func modelsReady() async -> Bool { ready }

    func prepareModels(progress: @Sendable @escaping (Double) -> Void) async throws {
        prepareCount += 1
        progress(0.5)
        progress(1)
        ready = true
    }

    func diarize(
        fileURL: URL,
        expectedSpeakers: SpeakerCountHint,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> [SpeakerTurn] {
        if let errorToThrow { throw errorToThrow }
        diarizedURLs.append(fileURL)
        hints.append(expectedSpeakers)
        progress(0.5)
        progress(1)
        return turnsToReturn
    }

    // MARK: Test controls

    func setError(_ error: DiarizationError?) { errorToThrow = error }
    func setReady(_ ready: Bool) { self.ready = ready }
    func setTurns(_ turns: [SpeakerTurn]) { turnsToReturn = turns }

    /// Two speakers alternating over the `FakeTranscriptionService.sampleWords` span.
    static let sampleTurns: [SpeakerTurn] = [
        SpeakerTurn(speakerID: "spk_a", start: 0, end: 3.6),
        SpeakerTurn(speakerID: "spk_b", start: 3.6, end: 7.0),
    ]
}
