import Foundation

/// Represents a single transcribed word with precise audio time boundaries (§7)
public struct TimedWord: Codable, Sendable, Hashable, Identifiable {
    public var id: String { "\(start)-\(end)-\(text)" }
    public var text: String
    public var start: TimeInterval
    public var end: TimeInterval
    
    public init(text: String, start: TimeInterval, end: TimeInterval) {
        self.text = text
        self.start = start
        self.end = end
    }
}
