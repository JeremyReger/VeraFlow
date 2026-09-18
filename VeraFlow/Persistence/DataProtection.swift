import Foundation
import os

/// Applies the data-at-rest policy to files SwiftData and FluidAudio create on their own
/// (security review S-6): the store holds transcripts and summaries and must be treated like the
/// audio, so it is excluded from iCloud backup and protected `completeUntilFirstUserAuthentication`
/// (the background pipeline writes it while the phone is locked). The model cache is excluded
/// from backup because it is large and re-downloadable.
enum DataProtection {
    private static let log = Logger(subsystem: "com.jeremyreger.veraflow", category: "data-protection")

    /// The SwiftData store files next to `storeURL` (the store, its write-ahead log, and its
    /// shared-memory file), whichever exist.
    static func storeFiles(for storeURL: URL) -> [URL] {
        let candidates = [storeURL, URL(filePath: storeURL.path + "-wal"), URL(filePath: storeURL.path + "-shm")]
        return candidates.filter { FileManager.default.fileExists(at: $0) }
    }

    /// Excludes `urls` from backup and sets `protection` on each. Errors are logged, never thrown:
    /// a missing attribute must not stop the app from starting.
    static func apply(to urls: [URL], protection: FileProtectionType = .completeUntilFirstUserAuthentication) {
        for url in urls {
            do {
                try setExcludedFromBackup(true, at: url)
                try FileManager.default.setAttributes([.protectionKey: protection], ofItemAtPath: url.path)
            } catch {
                log.error("could not protect \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    /// Backup exclusion only (directories whose contents are re-creatable, like the model cache).
    static func excludeFromBackup(_ url: URL) {
        do {
            try setExcludedFromBackup(true, at: url)
        } catch {
            log.error("could not exclude \(url.lastPathComponent, privacy: .public) from backup: \(error.localizedDescription, privacy: .private)")
        }
    }

    static func isExcludedFromBackup(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup) ?? false
    }

    private static func setExcludedFromBackup(_ excluded: Bool, at url: URL) throws {
        var mutable = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = excluded
        try mutable.setResourceValues(values)
    }
}
