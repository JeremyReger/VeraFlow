import Foundation
import Testing
@testable import VeraFlow

struct SilenceDetectorTests {
    /// 100 ms buckets: 1 s of speech, 3 s of room noise, 1 s of speech.
    private var speechGapSpeech: [Float] {
        Array(repeating: 0.5, count: 10) + Array(repeating: 0.01, count: 30) + Array(repeating: 0.6, count: 10)
    }

    @Test("A long pause becomes one range, trimmed by the padding on both sides")
    func findsGap() throws {
        let ranges = SilenceDetector.ranges(levels: speechGapSpeech, bucketDuration: 0.1)
        #expect(ranges.count == 1)
        let range = try #require(ranges.first)
        #expect(abs(range.start - 1.3) < 0.001)
        #expect(abs(range.end - 3.7) < 0.001)
        #expect(abs(SilenceDetector.totalDuration(ranges) - 2.4) < 0.001)
    }

    @Test("Pauses shorter than the minimum gap are pacing and stay")
    func ignoresShortGaps() {
        let levels: [Float] = Array(repeating: 0.5, count: 10) + Array(repeating: 0.01, count: 10) + Array(repeating: 0.5, count: 10)
        #expect(SilenceDetector.ranges(levels: levels, bucketDuration: 0.1).isEmpty)
        #expect(SilenceDetector.ranges(levels: levels, bucketDuration: 0.1, minimumGap: 0.8).count == 1)
    }

    @Test("Leading and trailing silence are ranges too")
    func edges() {
        let levels: [Float] = Array(repeating: 0.0, count: 20) + Array(repeating: 0.5, count: 10) + Array(repeating: 0.0, count: 20)
        let ranges = SilenceDetector.ranges(levels: levels, bucketDuration: 0.1)
        #expect(ranges.count == 2)
        #expect(ranges[0].start == 0.3)
        #expect(abs(ranges[1].end - 4.7) < 0.001)
    }

    @Test("An all-silent or flat file has no threshold, so nothing is skipped")
    func flatFiles() {
        #expect(SilenceDetector.threshold(for: Array(repeating: 0, count: 50)) == nil)
        #expect(SilenceDetector.threshold(for: Array(repeating: 0.4, count: 50)) == nil)
        #expect(SilenceDetector.threshold(for: [0.1, 0.9]) == nil, "too few buckets")
        #expect(SilenceDetector.ranges(levels: Array(repeating: 0, count: 50), bucketDuration: 0.1).isEmpty)
    }

    @Test("The threshold sits just above the room noise, so a quiet room still finds its pauses")
    func relativeThreshold() throws {
        let quietRoom: [Float] = Array(repeating: 0.002, count: 40) + Array(repeating: 0.05, count: 40)
        let threshold = try #require(SilenceDetector.threshold(for: quietRoom))
        #expect(threshold > 0.002 && threshold < 0.05)
        let loudRoom: [Float] = Array(repeating: 0.2, count: 40) + Array(repeating: 0.9, count: 40)
        let loud = try #require(SilenceDetector.threshold(for: loudRoom))
        #expect(loud > 0.2 && loud < 0.9)
    }

    @Test("The skip target is the end of the range the playhead is in")
    func skipTarget() {
        let ranges = [SilentRange(start: 1.3, end: 3.7), SilentRange(start: 10, end: 12)]
        #expect(SilenceDetector.skipTarget(at: 2, in: ranges) == 3.7)
        #expect(SilenceDetector.skipTarget(at: 1.3, in: ranges) == 3.7)
        #expect(SilenceDetector.skipTarget(at: 3.7, in: ranges) == nil)
        #expect(SilenceDetector.skipTarget(at: 5, in: ranges) == nil)
        #expect(SilenceDetector.skipTarget(at: 11, in: ranges) == 12)
    }
}
