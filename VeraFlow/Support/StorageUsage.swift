import Foundation

/// Bytes used by recordings on disk, for Settings → Storage (v1.1 plan item 5 and the parked
/// auto-archive request). Audio is the bulk; the SwiftData store is counted separately.
struct StorageUsage: Equatable, Sendable {
    var liveBytes: Int64 = 0
    var trashedBytes: Int64 = 0

    var totalBytes: Int64 { liveBytes + trashedBytes }

    /// Sums each recording's folder, split by whether it's in Recently Deleted.
    static func compute(recordings: [(id: UUID, isTrashed: Bool)], storage: RecordingStorage) -> StorageUsage {
        var usage = StorageUsage()
        for recording in recordings {
            let bytes = storage.folderSize(for: recording.id)
            if recording.isTrashed {
                usage.trashedBytes += bytes
            } else {
                usage.liveBytes += bytes
            }
        }
        return usage
    }

    static func text(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
