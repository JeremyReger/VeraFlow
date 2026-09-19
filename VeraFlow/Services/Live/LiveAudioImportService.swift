import AVFoundation
import Foundation

/// Copies an audio file picked from Files or handed over by the share sheet into a recording's
/// folder and reads its duration (SPEC §3, M2). Supports m4a, mp3, wav, caf, and the audio
/// track of mp4 / mov / m4v video (Teams and Zoom recordings), extracted on device.
actor LiveAudioImportService: AudioImportService {
    nonisolated let supportedExtensions: Set<String> = ["m4a", "mp3", "wav", "caf", "mp4", "mov", "m4v"]
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]

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

        let isVideo = Self.videoExtensions.contains(ext)
        let fileName = isVideo ? "audio.m4a" : "audio.\(ext)"
        let destination = destinationFolder.appending(path: fileName, directoryHint: .notDirectory)
        do {
            if FileManager.default.fileExists(at: destination) {
                try FileManager.default.removeItem(at: destination)
            }
            if isVideo {
                try await Self.extractAudio(from: sourceURL, to: destination)
            } else {
                try Self.coordinatedCopy(from: sourceURL, to: destination)
            }
        } catch let error as AudioImportError {
            throw error
        } catch {
            throw AudioImportError.copyFailed(error.localizedDescription)
        }

        guard let duration = try? AudioFileInfo.duration(of: destination), duration > 0 else {
            try? FileManager.default.removeItem(at: destination)
            throw AudioImportError.unreadable
        }

        DataProtection.protectNewFile(at: destination)
        return ImportedAudio(fileName: fileName, duration: duration)
    }

    /// Pulls the audio track out of a video file into an `.m4a`, without re-encoding when the
    /// track is already AAC. The video is copied to a temporary file first so iCloud items are
    /// downloaded and the export never holds the picker's URL.
    private static func extractAudio(from sourceURL: URL, to destination: URL) async throws {
        let temp = FileManager.default.temporaryDirectory
            .appending(path: "import-\(UUID().uuidString).\(sourceURL.pathExtension)", directoryHint: .notDirectory)
        defer { try? FileManager.default.removeItem(at: temp) }
        try coordinatedCopy(from: sourceURL, to: temp)
        let asset = AVURLAsset(url: temp)
        guard try await !asset.loadTracks(withMediaType: .audio).isEmpty else {
            throw AudioImportError.unreadable
        }
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw AudioImportError.unreadable
        }
        try await session.export(to: destination, as: .m4a)
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
