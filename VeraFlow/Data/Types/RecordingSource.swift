import Foundation

/// Origin source of a recording (§7)
public enum RecordingSource: String, Codable, Sendable {
    case recorded
    case imported
}
