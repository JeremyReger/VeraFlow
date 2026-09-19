import Foundation
import Testing
@testable import VeraFlow

struct WaveformPeaksTests {
    @Test("Buckets keep the loudest sample of each slice and scale the loudest bar to 1")
    func buckets() {
        let levels: [Float] = [0.1, 0.2, 0.4, 0.1, -0.8, 0.0, 0.2, 0.2]
        let bars = WaveformPeaks.buckets(levels, count: 4)
        #expect(bars.count == 4)
        #expect(bars[0] == 0.25)   // 0.2 / 0.8
        #expect(bars[1] == 0.5)    // 0.4 / 0.8
        #expect(bars[2] == 1)      // |-0.8|
        #expect(bars[3] == 0.25)
    }

    @Test("Silence and empty input give flat bars; zero bars gives nothing")
    func edges() {
        #expect(WaveformPeaks.buckets([], count: 3) == [0, 0, 0])
        #expect(WaveformPeaks.buckets([0, 0, 0, 0], count: 2) == [0, 0])
        #expect(WaveformPeaks.buckets([0.5], count: 0).isEmpty)
        // Fewer samples than bars: the tail is silence.
        #expect(WaveformPeaks.buckets([0.5, 0.25], count: 4) == [1, 0.5, 0, 0])
    }

    @Test("A tone file gives a full row of lit bars; a silent file gives none")
    func files() throws {
        let directory = try TestAudioFiles.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let tone = directory.appending(path: "tone.aac")
        try TestAudioFiles.writeToneAAC(to: tone, seconds: 1)
        let bars = try WaveformPeaks.compute(url: tone, barCount: 20)
        #expect(bars.count == 20)
        #expect(bars.max() == 1)
        // The encoder's first frames are quiet; every bar after the priming has signal.
        // The encoder pads the tail too, so the last bar may be partly silence.
        #expect(bars.dropFirst(2).dropLast(1).allSatisfy { $0 > 0.5 })

        let silent = directory.appending(path: "silent.caf")
        try TestAudioFiles.writeSilentCAF(to: silent, seconds: 1)
        #expect(try WaveformPeaks.compute(url: silent, barCount: 8) == Array(repeating: 0, count: 8))
    }

    @Test("Fine levels come one per bucket of time, un-normalised, and a silent file reads as zeros")
    func levels() throws {
        let directory = try TestAudioFiles.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let tone = directory.appending(path: "tone.aac")
        try TestAudioFiles.writeToneAAC(to: tone, seconds: 1)
        let levels = try WaveformPeaks.levels(url: tone, bucketDuration: 0.1)
        #expect((9...12).contains(levels.count), "about ten 100 ms buckets in one second (encoder padding allowed)")
        #expect(levels.dropFirst(2).dropLast(1).allSatisfy { $0 > 0.1 })

        let silent = directory.appending(path: "silent.caf")
        try TestAudioFiles.writeSilentCAF(to: silent, seconds: 1)
        let quiet = try WaveformPeaks.levels(url: silent, bucketDuration: 0.25)
        #expect(quiet.count == 4)
        #expect(quiet.allSatisfy { $0 == 0 })
        #expect(try WaveformPeaks.levels(url: silent, bucketDuration: 0).isEmpty)
    }
}
