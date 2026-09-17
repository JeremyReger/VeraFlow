import Foundation

/// Owns the on-disk layout for audio: `Application Support/Recordings/<uuid>/` (SPEC §6.2).
/// Folders are excluded from iCloud backup by default and use
/// `completeUntilFirstUserAuthentication` protection so recording keeps working while locked (SPEC §14.4).
struct RecordingStorage: Sendable {
    /// The `Recordings` directory that holds one folder per recording.
    let rootDirectory: URL

    /// Storage rooted in the app's Application Support directory.
    static func appDefault() throws -> RecordingStorage {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return RecordingStorage(rootDirectory: support.appending(path: "Recordings", directoryHint: .isDirectory))
    }

    init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    /// The folder for one recording. Creates it if needed.
    @discardableResult
    func folder(for id: UUID, excludeFromBackup: Bool = true) throws -> URL {
        let url = rootDirectory.appending(path: id.uuidString, directoryHint: .isDirectory)
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: url.path()) {
            try fileManager.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
        }
        try setExcludedFromBackup(excludeFromBackup, at: url)
        return url
    }

    /// Full URL of a recording's audio file.
    func audioURL(for id: UUID, fileName: String) -> URL {
        rootDirectory
            .appending(path: id.uuidString, directoryHint: .isDirectory)
            .appending(path: fileName, directoryHint: .notDirectory)
    }

    /// Deletes a recording's folder and everything in it. Missing folders are not an error.
    func deleteFolder(for id: UUID) throws {
        let url = rootDirectory.appending(path: id.uuidString, directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: url.path()) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// IDs of every recording folder on disk. Used for crash recovery and orphan cleanup.
    func existingFolderIDs() throws -> [UUID] {
        guard FileManager.default.fileExists(atPath: rootDirectory.path()) else { return [] }
        let contents = try FileManager.default.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return contents.compactMap { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            return UUID(uuidString: url.lastPathComponent)
        }
    }

    /// Flips the iCloud backup exclusion on every recording folder (Settings toggle, SPEC §6.2).
    func setExcludedFromBackupForAll(_ excluded: Bool) throws {
        for id in try existingFolderIDs() {
            let url = rootDirectory.appending(path: id.uuidString, directoryHint: .isDirectory)
            try setExcludedFromBackup(excluded, at: url)
        }
    }

    /// Free space on the volume that holds the recordings, in bytes. `nil` if it can't be read.
    func availableCapacity() -> Int64? {
        let values = try? rootDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    private func setExcludedFromBackup(_ excluded: Bool, at url: URL) throws {
        var mutable = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = excluded
        try mutable.setResourceValues(values)
    }
}
