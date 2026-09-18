import Foundation
import os

/// Removes leftovers that hold user content outside the protected recording folders: export
/// files in `tmp/Exports`, Photos-picker copies in `tmp/PhotoImports`, and share-sheet files in
/// `Documents/Inbox` that a failed or interrupted import left behind (security review S-5, S-7, S-8).
/// iOS purges `tmp` eventually, not promptly; this runs at every launch.
enum TemporaryFiles {
    private static let log = Logger(subsystem: "com.jeremyreger.veraflow", category: "cleanup")

    /// The folders swept in the app.
    static func appDefaultDirectories() -> [URL] {
        let tmp = FileManager.default.temporaryDirectory
        var urls = [
            tmp.appending(path: "Exports", directoryHint: .isDirectory),
            tmp.appending(path: "PhotoImports", directoryHint: .isDirectory),
        ]
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            urls.append(documents.appending(path: "Inbox", directoryHint: .isDirectory))
        }
        return urls
    }

    /// Deletes every item inside each directory (not the directory itself). Missing directories
    /// are fine. Returns the number of items removed.
    @discardableResult
    static func sweep(_ directories: [URL] = appDefaultDirectories()) -> Int {
        let fileManager = FileManager.default
        var removed = 0
        for directory in directories {
            guard let items = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { continue }
            for item in items {
                do {
                    try fileManager.removeItem(at: item)
                    removed += 1
                } catch {
                    log.error("could not remove a temporary file: \(error.localizedDescription, privacy: .private)")
                }
            }
        }
        if removed > 0 {
            log.info("removed \(removed, privacy: .public) leftover temporary files")
        }
        return removed
    }
}
