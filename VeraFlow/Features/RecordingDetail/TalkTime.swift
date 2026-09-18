import Foundation

/// How long each labelled speaker talked, for the Audio tab's per-voice rows (design spec §4).
struct TalkTimeShare: Equatable, Sendable {
    let speakerKey: String
    let seconds: TimeInterval
    /// This speaker's share of all labelled speech, 0...1.
    let fraction: Double
}

enum TalkTime {
    /// Sums segment lengths per speaker. Unlabelled segments are left out; the fractions are
    /// of the labelled total. Longest talker first, ties by key.
    static func shares(segments: [(speakerKey: String?, start: TimeInterval, end: TimeInterval)]) -> [TalkTimeShare] {
        var totals: [String: TimeInterval] = [:]
        for segment in segments {
            guard let key = segment.speakerKey else { continue }
            totals[key, default: 0] += max(0, segment.end - segment.start)
        }
        let labelled = totals.values.reduce(0, +)
        return totals
            .map { key, seconds in
                TalkTimeShare(speakerKey: key, seconds: seconds, fraction: labelled > 0 ? seconds / labelled : 0)
            }
            .sorted { lhs, rhs in
                lhs.seconds == rhs.seconds ? lhs.speakerKey < rhs.speakerKey : lhs.seconds > rhs.seconds
            }
    }
}
