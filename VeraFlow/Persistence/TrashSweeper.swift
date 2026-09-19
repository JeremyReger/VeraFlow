import Foundation
import SwiftData

/// Recently Deleted (v1.1 plan item 10): a deleted recording keeps its row and audio for
/// `retention`, can be restored, and is removed for good by the sweep at launch.
enum TrashPolicy {
    static let retention: TimeInterval = 30 * 24 * 60 * 60

    /// Whole days left before the sweep removes a recording trashed at `deletedAt`; never negative.
    static func daysRemaining(deletedAt: Date, now: Date = .now) -> Int {
        let left = retention - now.timeIntervalSince(deletedAt)
        return max(0, Int((left / 86_400).rounded(.up)))
    }

    static func isExpired(deletedAt: Date, now: Date = .now) -> Bool {
        now.timeIntervalSince(deletedAt) >= retention
    }
}

/// Removes trashed recordings past their retention, rows and audio folders both. Runs on launch
/// next to `RecordingRecovery`.
@MainActor
struct TrashSweeper {
    let context: ModelContext
    let storage: RecordingStorage

    /// Returns the IDs removed.
    @discardableResult
    func sweep(now: Date = .now) throws -> [UUID] {
        let expired = try context.fetch(FetchDescriptor<Recording>()).filter { recording in
            guard let deletedAt = recording.deletedAt else { return false }
            return TrashPolicy.isExpired(deletedAt: deletedAt, now: now)
        }
        guard !expired.isEmpty else { return [] }
        var removed: [UUID] = []
        for recording in expired {
            let id = recording.id
            context.delete(recording)
            removed.append(id)
        }
        try context.save()
        for id in removed {
            try? storage.deleteFolder(for: id)
        }
        return removed
    }
}
