import Foundation
import SwiftData

/// Represents an identified speaker in a recording (§7, §10)
@Model
public final class Speaker {
    public var key: String          // e.g., "S1", "S2"
    public var displayName: String  // e.g., "Speaker 1" (editable to user's name)
    public var colorIndex: Int      // Index for UI color assignment
    
    public init(key: String, displayName: String, colorIndex: Int = 0) {
        self.key = key
        self.displayName = displayName
        self.colorIndex = colorIndex
    }
}
