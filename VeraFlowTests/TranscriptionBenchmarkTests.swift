import Foundation
import Testing
@testable import VeraFlow

struct TranscriptionBenchmarkTests {
    @Test("Each engine is timed and scored against the reference; failures are reported, not thrown")
    func runsEngines() async {
        let good = FakeTranscriptionService()
        let broken = FakeTranscriptionService()
        await broken.setError(.analysisFailed("nope"))
        let reference = FakeTranscriptionService.sampleWords.map(\.text).joined(separator: " ")

        let outcomes = await TranscriptionBenchmark.run(
            engines: [.init(name: "Good", service: good), .init(name: "Broken", service: broken)],
            fileURL: URL(filePath: "/tmp/x.aac"),
            audioSeconds: 6,
            locale: Locale(identifier: "en-US"),
            reference: reference
        )

        #expect(outcomes.count == 2)
        #expect(outcomes[0].engineName == "Good")
        #expect(outcomes[0].wordCount == FakeTranscriptionService.sampleWords.count)
        #expect(outcomes[0].wordErrorRate?.rate == 0)
        #expect(outcomes[0].errorMessage == nil)
        #expect(outcomes[0].seconds >= 0)
        #expect(outcomes[1].errorMessage == "Transcription failed: nope")
        #expect(outcomes[1].wordCount == 0)
    }

    @Test("Without a reference there is no error rate, and missing assets are downloaded first")
    func noReference() async {
        let engine = FakeTranscriptionService()
        await engine.setAssetStatus(.downloadRequired)
        let outcomes = await TranscriptionBenchmark.run(
            engines: [.init(name: "Only", service: engine)],
            fileURL: URL(filePath: "/tmp/x.aac"),
            audioSeconds: 6,
            locale: Locale(identifier: "en-US"),
            reference: "   "
        )
        #expect(outcomes[0].wordErrorRate == nil)
        #expect(await engine.prepareCount == 1)
    }
}

extension TranscriptionBenchmarkTests {
    @Test("The report is a Markdown table with one row per engine")
    func report() {
        let outcomes = [
            TranscriptionBenchmark.Outcome(
                engineName: "Apple Speech", seconds: 30, audioSeconds: 600, wordCount: 1_500,
                transcript: "x", wordErrorRate: .init(substitutions: 5, deletions: 3, insertions: 2, referenceCount: 100), errorMessage: nil
            ),
            TranscriptionBenchmark.Outcome(
                engineName: "Parakeet", seconds: 1, audioSeconds: 600, wordCount: 0,
                transcript: "", wordErrorRate: nil, errorMessage: "Transcription failed: nope"
            ),
        ]
        let report = TranscriptionBenchmark.report(outcomes, fixtureName: "02-meeting-2p-10min")
        let lines = report.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines[0].contains("02-meeting-2p-10min"))
        #expect(lines[0].contains("600 s"))
        #expect(lines.count == 6)
        #expect(lines[4] == "| Apple Speech | 30.0 s | 20.0× real time | 1500 | 10.0% |  |")
        #expect(lines[5] == "| Parakeet | 1.0 s | 600.0× real time | 0 | — | Transcription failed: nope |")
    }
}

@MainActor
struct TranscriptionBenchmarkModelTests {
    @Test("The model runs the engines once, tracks progress, and exposes the outcomes")
    func runs() async {
        let model = TranscriptionBenchmarkModel()
        let engine = FakeTranscriptionService()
        #expect(!model.isRunning)

        await model.run(
            engines: [.init(name: "Fake", service: engine)],
            fixtureName: "sample",
            fileURL: URL(filePath: "/tmp/x.aac"),
            audioSeconds: 6,
            locale: Locale(identifier: "en-US"),
            reference: nil
        )

        #expect(!model.isRunning)
        #expect(model.outcomes.count == 1)
        #expect(model.outcomes[0].engineName == "Fake")
        #expect(await engine.transcribedURLs.count == 1)
        #expect(model.report.contains("| Fake |"))
        // Progress callbacks hop to the main actor; give them a turn to land.
        await Task.yield()
        #expect((model.progress["Fake"] ?? 0) > 0)
    }
}
