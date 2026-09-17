import Foundation
import AVFoundation

/// Production implementation of AudioImportServiceProtocol (§6.1, §16 M2)
/// Safely imports external audio files from Files app or Share Sheet into local storage.
public final class AudioImportService: AudioImportServiceProtocol, Sendable {
    private static let supportedExtensions: Set<String> = [
        "m4a", "mp3", "wav", "caf", "aac", "aif", "aiff"
    ]
    
    public init() {}
    
    public func isSupportedAudioFile(at url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return Self.supportedExtensions.contains(ext)
    }
    
    public func importAudio(
        from sourceURL: URL,
        destinationDirectory: URL
    ) async throws -> (fileURL: URL, duration: TimeInterval, title: String) {
        // 1. Security-scoped resource handling for Files app picker and Share Sheet
        let isSecurityScoped = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        
        // 2. Format validation
        guard isSupportedAudioFile(at: sourceURL) else {
            throw AudioImportError.unsupportedFormat(sourceURL.pathExtension)
        }
        
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw AudioImportError.fileNotFound
        }
        
        // 3. Extract exact duration asynchronously using AVURLAsset
        let asset = AVURLAsset(url: sourceURL)
        var duration: TimeInterval = 0
        
        do {
            let cmDuration = try await asset.load(.duration)
            duration = CMTimeGetSeconds(cmDuration)
        } catch {
            // Fallback to AVAudioFile
            if let file = try? AVAudioFile(forReading: sourceURL) {
                let sampleRate = file.processingFormat.sampleRate
                if sampleRate > 0 {
                    duration = Double(file.length) / sampleRate
                }
            }
        }
        
        // 4. Validate audio length
        guard duration.isFinite && duration > 0 else {
            throw AudioImportError.corruptOrEmptyAudio
        }
        
        // 5. Clean up display title from filename
        let rawTitle = sourceURL.deletingPathExtension().lastPathComponent
        let sanitizedTitle = cleanTitle(rawTitle)
        
        // 6. Ensure destination directory exists
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        
        // 7. Copy file into app sandbox
        let ext = sourceURL.pathExtension.lowercased()
        let destinationURL = destinationDirectory.appendingPathComponent("audio.\(ext)")
        
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            throw AudioImportError.copyFailed(error.localizedDescription)
        }
        
        return (destinationURL, duration, sanitizedTitle)
    }
    
    private func cleanTitle(_ raw: String) -> String {
        var title = raw.replacingOccurrences(of: "_", with: " ")
        title = title.replacingOccurrences(of: "-", with: " ")
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Imported Recording" : title
    }
}

public enum AudioImportError: LocalizedError, Sendable {
    case fileNotFound
    case unsupportedFormat(String)
    case corruptOrEmptyAudio
    case copyFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .fileNotFound:
            "Audio file could not be found at the specified location."
        case .unsupportedFormat(let ext):
            "The audio format '.\(ext)' is not supported. Please choose a .m4a, .mp3, .wav, or .caf file."
        case .corruptOrEmptyAudio:
            "The selected file contains no readable audio or is corrupted."
        case .copyFailed(let reason):
            "Failed to copy audio file to local storage: \(reason)"
        }
    }
}
