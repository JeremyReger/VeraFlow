import Foundation
import SwiftData

/// A speaker detected in a recording (SPEC §7, §10).
@Model
final class Speaker {
    /// Stable key such as "S1". Summaries reference this, not the display name.
    var key: String
    /// "Speaker 1" until the user renames it.
    var displayName: String
    var colorIndex: Int

    var recording: Recording?

    init(key: String, displayName: String, colorIndex: Int) {
        self.key = key
        self.displayName = displayName
        self.colorIndex = colorIndex
    }

    /// Makes the default speaker for position `number` (1-based).
    static func `default`(number: Int) -> Speaker {
        Speaker(key: "S\(number)", displayName: "Speaker \(number)", colorIndex: (number - 1) % 8)
    }
}
