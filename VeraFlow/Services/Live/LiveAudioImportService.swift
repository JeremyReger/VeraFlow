import Foundation

/// Copies an audio file picked from Files or handed over by the share sheet into a recording's
/// folder and reads its duration (SPEC §3, M2). Supports m4a, mp3, wav, caf.
actor LiveAudioImportService: AudioImportService {
    nonisolated let supportedExtensions: Set<String> = ["m4a", "mp3", "wav", "caf"]

    func importAudio(from sourceURL: URL, into destinationFolder: URL) async throws -> ImportedAudio {
        let ext = sourceURL.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else {
            throw AudioImportError.unsupportedType(ext)
        }

        // Document-picker URLs are security scoped; Inbox URLs (share sheet) are not, and the call
        // returns false for them, which is fine.
        let isScoped = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if isScoped { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let fileName = "audio.\(ext)"
        let destination = destinationFolder.appending(path: fileName, directoryHint: .notDirectory)
        do {
            if FileManager.default.fileExists(at: destination) {
                try FileManager.default.removeItem(at: destination)
            }
            try Self.coordinatedCopy(from: sourceURL, to: destination)
        } catch {
            throw AudioImportError.copyFailed(error.localizedDescription)
        }

        guard let duration = try? AudioFileInfo.duration(of: destination), duration > 0 else {
            try? FileManager.default.removeItem(at: destination)
            throw AudioImportError.unreadable
        }

        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: destination.path(percentEncoded: false)
        )
        return ImportedAudio(fileName: fileName, duration: duration)
    }

    /// Reads through a file coordinator so iCloud Drive items are downloaded before the copy.
    private static func coordinatedCopy(from source: URL, to destination: URL) throws {
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { readableURL in
            do {
                try FileManager.default.copyItem(at: readableURL, to: destination)
            } catch {
                copyError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
    }
}
