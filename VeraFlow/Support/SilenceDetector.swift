import Foundation

/// A stretch of a recording with nothing worth hearing.
struct SilentRange: Equatable, Sendable {
    var start: TimeInterval
    var end: TimeInterval

    var duration: TimeInterval { max(0, end - start) }
}

/// Finds the pauses playback can jump over (SPEC §4.4 "skip silence", v1.1 plan item 9).
/// Works on coarse peak levels (one per `bucketDuration`) read once per recording, so a quiet
/// room and a loud one both work: the threshold sits a little above the file's own noise floor.
enum SilenceDetector {
    /// A pause shorter than this is pacing, not silence.
    static let defaultMinimumGap: TimeInterval = 1.5
    /// Kept on both sides of every jump so sentences don't run into each other.
    static let defaultPadding: TimeInterval = 0.3
    /// How far above the noise floor (towards the speech level) a bucket must reach to count as speech.
    static let floorFraction: Float = 0.12
    /// Below this absolute level everything is silence, whatever the percentiles say.
    static let absoluteFloor: Float = 0.004

    /// The level under which a bucket is silent: the 20th percentile (the room) plus a slice of
    /// the way up to the 95th percentile (the talking; high enough that a recording which is
    /// mostly pauses still finds its speech). A file with no dynamic range gives no threshold,
    /// so nothing is skipped.
    static func threshold(for levels: [Float]) -> Float? {
        guard levels.count >= 4 else { return nil }
        let sorted = levels.map { abs($0) }.sorted()
        let floor = sorted[Int(Double(sorted.count - 1) * 0.2)]
        let speech = sorted[Int(Double(sorted.count - 1) * 0.95)]
        guard speech > floor * 1.5, speech > absoluteFloor else { return nil }
        return max(absoluteFloor, floor + floorFraction * (speech - floor))
    }

    /// Runs of quiet buckets at least `minimumGap` long, trimmed by `padding` on each side.
    static func ranges(
        levels: [Float],
        bucketDuration: TimeInterval,
        minimumGap: TimeInterval = defaultMinimumGap,
        padding: TimeInterval = defaultPadding
    ) -> [SilentRange] {
        guard bucketDuration > 0, let threshold = threshold(for: levels) else { return [] }
        var result: [SilentRange] = []
        var runStart: Int?
        func close(at endIndex: Int) {
            guard let start = runStart else { return }
            runStart = nil
            let range = SilentRange(
                start: TimeInterval(start) * bucketDuration + padding,
                end: TimeInterval(endIndex) * bucketDuration - padding
            )
            let raw = TimeInterval(endIndex - start) * bucketDuration
            if raw >= minimumGap, range.duration > 0 {
                result.append(range)
            }
        }
        for (index, level) in levels.enumerated() {
            if abs(level) < threshold {
                if runStart == nil { runStart = index }
            } else {
                close(at: index)
            }
        }
        close(at: levels.count)
        return result
    }

    static func totalDuration(_ ranges: [SilentRange]) -> TimeInterval {
        ranges.reduce(0) { $0 + $1.duration }
    }

    /// Where playback should jump to when `time` is inside a silent range; `nil` when it isn't.
    static func skipTarget(at time: TimeInterval, in ranges: [SilentRange]) -> TimeInterval? {
        ranges.first { $0.start <= time && time < $0.end }?.end
    }
}
