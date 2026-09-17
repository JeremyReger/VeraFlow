import Foundation

/// Free-space thresholds for recording (SPEC §8.3): warn under 500 MB, stop under 100 MB.
enum DiskSpacePolicy {
    enum Verdict: Equatable {
        case ok
        case warn
        case stop
    }

    static let warnBelowBytes: Int64 = 500 * 1_000_000
    static let stopBelowBytes: Int64 = 100 * 1_000_000

    /// `nil` means the free space couldn't be read; recording continues.
    static func evaluate(availableBytes: Int64?) -> Verdict {
        guard let availableBytes else { return .ok }
        if availableBytes < stopBelowBytes { return .stop }
        if availableBytes < warnBelowBytes { return .warn }
        return .ok
    }

    /// Rough recording size at the SPEC §8.2 bitrate (~64 kbps AAC), for "about N minutes left" copy.
    static let bytesPerSecond: Int64 = 8_000

    static func secondsRemaining(availableBytes: Int64) -> TimeInterval {
        let usable = max(0, availableBytes - stopBelowBytes)
        return TimeInterval(usable / bytesPerSecond)
    }
}
