import Foundation

/// An audio file copied into the app's storage.
struct ImportedAudio: Sendable, Equatable {
    var fileName: String
    var duration: TimeInterval
}

enum AudioImportError: Error, Equatable {
    case unsupportedType(String)
    case unreadable
    case copyFailed(String)
}

/// Imports audio from the Files app or share sheet (SPEC §3, M2). Supports m4a, mp3, wav, caf.
protocol AudioImportService: Sendable {
    /// File extensions (lowercase, no dot) this importer accepts.
    var supportedExtensions: Set<String> { get }
    /// Copies `sourceURL` into `destinationFolder` and reads its duration.
    /// Handles security-scoped URLs from the document picker.
    func importAudio(from sourceURL: URL, into destinationFolder: URL) async throws -> ImportedAudio
}

/// Copies the file without inspecting it and reports a fixed duration.
actor FakeAudioImportService: AudioImportService {
    nonisolated let supportedExtensions: Set<String> = ["m4a", "mp3", "wav", "caf"]
    var fixedDuration: TimeInterval
    private(set) var importedURLs: [URL] = []

    init(fixedDuration: TimeInterval = 90) {
        self.fixedDuration = fixedDuration
    }

    func importAudio(from sourceURL: URL, into destinationFolder: URL) async throws -> ImportedAudio {
        let ext = sourceURL.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else { throw AudioImportError.unsupportedType(ext) }
        let fileName = "audio.\(ext)"
        let destination = destinationFolder.appending(path: fileName, directoryHint: .notDirectory)
        if FileManager.default.fileExists(at: sourceURL) {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: sourceURL, to: destination)
        }
        importedURLs.append(sourceURL)
        return ImportedAudio(fileName: fileName, duration: fixedDuration)
    }
}
