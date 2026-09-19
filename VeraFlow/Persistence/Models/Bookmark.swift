import Foundation
import SwiftData

/// Why a mark exists: the user tapped Mark, or the recorder paused for a call.
enum BookmarkKind: String, Codable, Sendable {
    case manual
    case interrupted
}

/// A flagged moment in a recording (SPEC §4.2, §7). v1.1: the user's marks reach the transcript
/// and the summarizer (plan item 1); `note` holds the one-word label chosen after Mark.
@Model
final class Bookmark {
    var time: TimeInterval
    var note: String?
    /// Added in v1.1 with a default so existing rows migrate in place; older rows are all manual
    /// except the ones whose note says "Interrupted" (see `isUserMark`).
    var kind: BookmarkKind = BookmarkKind.manual

    var recording: Recording?

    init(time: TimeInterval, note: String? = nil, kind: BookmarkKind = .manual) {
        self.time = time
        self.note = note
        self.kind = kind
    }

    /// The pre-1.1 interrupted mark carried only its note; both spellings count.
    var isUserMark: Bool {
        kind == .manual && note != Bookmark.interruptedNote
    }

    static let interruptedNote = "Interrupted"

    /// The labels the recorder offers right after Mark (design spec §4 Record — running).
    static let quickLabels = ["Decision", "To-do", "Quote", "Question"]
}
