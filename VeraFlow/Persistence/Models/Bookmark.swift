import Foundation
import SwiftData

/// A flagged moment in a recording (SPEC §4.2, §7).
@Model
final class Bookmark {
    var time: TimeInterval
    var note: String?

    var recording: Recording?

    init(time: TimeInterval, note: String? = nil) {
        self.time = time
        self.note = note
    }
}
