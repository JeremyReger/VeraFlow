import Foundation

/// Where a recording's audio came from (SPEC §7).
enum RecordingSource: String, Codable, Sendable {
    case recorded
    case imported
}
