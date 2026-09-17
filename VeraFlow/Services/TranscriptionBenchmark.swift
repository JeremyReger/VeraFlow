import Foundation

/// Runs several engines on the same file and compares speed and accuracy (SPEC §9.4, §16 M3).
enum TranscriptionBenchmark {
    struct Engine: Sendable {
        var name: String
        var service: any TranscriptionService
    }

    struct Outcome: Sendable, Equatable {
        var engineName: String
        var seconds: TimeInterval
        var audioSeconds: TimeInterval
        var wordCount: Int
        var transcript: String
        /// Present only when a reference text was supplied.
        var wordErrorRate: WordErrorRate.Score?
        var errorMessage: String?

        /// How many seconds of audio are processed per second of wall clock.
        var realTimeFactor: Double { seconds > 0 ? audioSeconds / seconds : 0 }
    }

    static func run(
        engines: [Engine],
        fileURL: URL,
        audioSeconds: TimeInterval,
        locale: Locale,
        reference: String?,
        onProgress: @Sendable @escaping (String, Double) -> Void = { _, _ in }
    ) async -> [Outcome] {
        var outcomes: [Outcome] = []
        for engine in engines {
            let name = engine.name
            let clock = ContinuousClock()
            let started = clock.now
            do {
                if await engine.service.assetStatus(for: locale) == .downloadRequired {
                    try await engine.service.prepareAssets(for: locale) { onProgress(name, $0 * 0.1) }
                }
                let result = try await engine.service.transcribe(fileURL: fileURL, locale: locale) { onProgress(name, 0.1 + $0 * 0.9) }
                let seconds = Self.seconds(clock.now - started)
                let transcript = result.words.map(\.text).joined(separator: " ")
                let score = reference.flatMap { ref -> WordErrorRate.Score? in
                    let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : WordErrorRate.score(reference: trimmed, hypothesis: transcript)
                }
                outcomes.append(Outcome(
                    engineName: name,
                    seconds: seconds,
                    audioSeconds: audioSeconds,
                    wordCount: result.words.count,
                    transcript: transcript,
                    wordErrorRate: score,
                    errorMessage: nil
                ))
            } catch {
                outcomes.append(Outcome(
                    engineName: name,
                    seconds: Self.seconds(clock.now - started),
                    audioSeconds: audioSeconds,
                    wordCount: 0,
                    transcript: "",
                    wordErrorRate: nil,
                    errorMessage: PipelineFailure.message(for: error)
                ))
            }
            onProgress(name, 1)
        }
        return outcomes
    }

    /// Markdown table of the outcomes, ready to paste into `docs/DECISIONS.md`.
    static func report(_ outcomes: [Outcome], fixtureName: String) -> String {
        var lines = [
            "Benchmark on `\(fixtureName)` (\(Int(outcomes.first?.audioSeconds ?? 0)) s of audio)",
            "",
            "| Engine | Time | Speed | Words | WER | Note |",
            "|---|---|---|---|---|---|",
        ]
        for outcome in outcomes {
            let wer = outcome.wordErrorRate.map { String(format: "%.1f%%", $0.rate * 100) } ?? "—"
            let speed = outcome.seconds > 0 ? String(format: "%.1f× real time", outcome.realTimeFactor) : "—"
            let note = outcome.errorMessage ?? ""
            lines.append("| \(outcome.engineName) | \(String(format: "%.1f s", outcome.seconds)) | \(speed) | \(outcome.wordCount) | \(wer) | \(note) |")
        }
        return lines.joined(separator: "\n")
    }

    private static func seconds(_ duration: Duration) -> TimeInterval {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
