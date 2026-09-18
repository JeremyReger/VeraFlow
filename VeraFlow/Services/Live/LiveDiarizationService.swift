import CoreML
import FluidAudio
import Foundation
import os

/// Speaker diarization with FluidAudio's offline pipeline (SPEC §10.1): pyannote-style
/// segmentation + embeddings + clustering, all Core ML on device. Models download once from
/// Hugging Face into Application Support/FluidAudio/Models (SPEC §14.1).
///
/// Verified against FluidAudio 0.15.7 source: `OfflineDiarizerModels.load(from:configuration:progressHandler:)`,
/// `OfflineDiarizerManager(config:)`, `initialize(models:)`, `process(_ url:progressCallback:)`,
/// `DiarizationResult.segments: [TimedSpeakerSegment]`, `OfflineDiarizerConfig.clustering.numSpeakers/minSpeakers`.
actor LiveDiarizationService: DiarizationService {
    private static let log = Logger(subsystem: "com.jeremyreger.veraflow", category: "diarization")

    /// Loaded once per launch; the struct is Sendable so it can live in the actor.
    private var models: OfflineDiarizerModels?

    func modelsReady() async -> Bool {
        if models != nil { return true }
        return Self.cachedModelsExist()
    }

    func prepareModels(progress: @Sendable @escaping (Double) -> Void) async throws {
        if models != nil {
            progress(1)
            return
        }
        do {
            // CPU + Neural Engine only. iOS refuses Metal (GPU) work from a backgrounded app, and
            // the pipeline runs right after Stop while the user has often already left the app:
            // on device every segmentation call failed with "Insufficient Permission (to submit
            // GPU work from background)". The ANE is not Metal and keeps working.
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .cpuAndNeuralEngine
            let loaded = try await OfflineDiarizerModels.load(configuration: configuration) { update in
                progress(min(0.99, update.fractionCompleted))
            }
            models = loaded
            progress(1)
            Self.log.info("diarizer models ready (compiled in \(loaded.compilationDuration, format: .fixed(precision: 1), privacy: .public)s)")
        } catch {
            throw DiarizationError.modelDownloadFailed(error.localizedDescription)
        }
    }

    func diarize(
        fileURL: URL,
        expectedSpeakers: SpeakerCountHint,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> [SpeakerTurn] {
        if models == nil {
            // Files are cached from an earlier launch; load them now (no download needed).
            try await prepareModels { _ in }
        }
        guard let models else { throw DiarizationError.modelsNotReady }

        var config = OfflineDiarizerConfig.default
        config.clustering.numSpeakers = expectedSpeakers.exact
        config.clustering.minSpeakers = expectedSpeakers.minimum
        // Off by default in FluidAudio. Without it, a speaker whose turns fall in frames with no
        // clustering votes is silently absorbed into the surrounding speaker: on Jeremy's 4:40
        // recording "Expected speakers: 3" produced 3 centroids but only 2 labelled speakers.
        config.zeroVoteReembed.enabled = true
        // A fresh manager per file: the class isn't Sendable and the speaker hint is part of its config.
        let manager = OfflineDiarizerManager(config: config)
        manager.initialize(models: models)

        let result: DiarizationResult
        do {
            result = try await manager.process(fileURL) { done, total in
                guard total > 0 else { return }
                progress(min(0.99, Double(done) / Double(total)))
            }
        } catch OfflineDiarizationError.noSpeechDetected {
            Self.log.info("no speech detected; single speaker")
            progress(1)
            return []
        } catch {
            throw DiarizationError.processingFailed(error.localizedDescription)
        }
        try Task.checkCancellation()
        progress(1)

        let turns = result.segments
            .map { SpeakerTurn(speakerID: $0.speakerId, start: TimeInterval($0.startTimeSeconds), end: TimeInterval($0.endTimeSeconds)) }
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }
        let speakerCount = Set(turns.map(\.speakerID)).count
        Self.log.info("diarized \(fileURL.lastPathComponent, privacy: .public): \(turns.count, privacy: .public) turns, \(speakerCount, privacy: .public) speakers")
        return turns
    }

    /// True when every required compiled model is in FluidAudio's cache folder, so no download
    /// is needed. Mirrors where `ModelHub` puts them; a false negative only costs a re-check by the loader.
    nonisolated static func cachedModelsExist() -> Bool {
        let folder = OfflineDiarizerModels.defaultModelsDirectory()
            .appendingPathComponent(Repo.diarizer.folderName, isDirectory: true)
        let required = [
            ModelNames.OfflineDiarizer.segmentationFile,
            ModelNames.OfflineDiarizer.fbankFile,
            ModelNames.OfflineDiarizer.embeddingFile,
            ModelNames.OfflineDiarizer.pldaRhoFile,
        ]
        return required.allSatisfy { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }
    }
}
