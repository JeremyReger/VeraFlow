import Foundation
import SwiftData

/// Time-stamped bookmark flagged during or after recording (§7, §8)
@Model
public final class Bookmark {
    public var time: TimeInterval
    public var note: String?
    public var createdAt: Date
    
    public init(time: TimeInterval, note: String? = nil, createdAt: Date = Date()) {
        self.time = time
        self.note = note
        self.createdAt = createdAt
    }
}
