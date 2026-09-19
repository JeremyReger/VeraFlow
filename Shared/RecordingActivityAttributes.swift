import Foundation
#if os(iOS)
import ActivityKit
#endif

/// What the Live Activity shows while recording (Lock Screen banner and Dynamic Island).
/// Lives in the top-level Shared/ folder because it is compiled into both the app and the
/// widget extension; keep it to plain data. ActivityKit imports on the Mac but every one of its
/// types is marked unavailable there, so the conformance is guarded on `os(iOS)` — not on
/// `canImport` — and the recorder's state stays plain `Codable` data on the Mac.
struct RecordingActivityAttributes: Codable, Hashable, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        /// Wall-clock moment the timer counts up from: "now minus audio recorded so far".
        /// Re-derived from the recorder's frame count on every update, so pauses never drift it.
        var startedAt: Date
        /// Set while paused; the widget freezes its timer at this moment.
        var pausedAt: Date?
        var bookmarkCount: Int

        var isPaused: Bool { pausedAt != nil }

        /// Builds the state from what the recorder knows. `elapsed` is seconds of audio written.
        static func make(elapsed: TimeInterval, isPaused: Bool, bookmarkCount: Int, now: Date) -> ContentState {
            ContentState(
                startedAt: now.addingTimeInterval(-max(0, elapsed)),
                pausedAt: isPaused ? now : nil,
                bookmarkCount: bookmarkCount
            )
        }
    }

    var recordingID: UUID
    var title: String
}

#if os(iOS)
extension RecordingActivityAttributes: ActivityAttributes {}
#endif
