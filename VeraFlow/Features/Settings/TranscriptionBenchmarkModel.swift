import Foundation
import Observation

/// Drives the debug benchmark screen: runs every engine on one recording and keeps the
/// per-engine progress and the outcomes for display (SPEC §9.4).
@Observable
@MainActor
final class TranscriptionBenchmarkModel {
    private(set) var isRunning = false
    /// 0...1 per engine name while running.
    private(set) var progress: [String: Double] = [:]
    private(set) var outcomes: [TranscriptionBenchmark.Outcome] = []
    private(set) var fixtureName = ""

    func run(
        engines: [TranscriptionBenchmark.Engine],
        fixtureName: String,
        fileURL: URL,
        audioSeconds: TimeInterval,
        locale: Locale,
        reference: String?
    ) async {
        guard !isRunning else { return }
        isRunning = true
        progress = [:]
        outcomes = []
        self.fixtureName = fixtureName
        let results = await TranscriptionBenchmark.run(
            engines: engines,
            fileURL: fileURL,
            audioSeconds: audioSeconds,
            locale: locale,
            reference: reference,
            onProgress: { name, fraction in
                Task { @MainActor in self.progress[name] = fraction }
            }
        )
        outcomes = results
        isRunning = false
    }

    /// Markdown table for `docs/DECISIONS.md`.
    var report: String {
        TranscriptionBenchmark.report(outcomes, fixtureName: fixtureName)
    }
}
