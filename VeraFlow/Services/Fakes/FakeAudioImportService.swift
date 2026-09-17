import Foundation

public final class FakeAudioImportService: AudioImportServiceProtocol, Sendable {
    public init() {}
    
    public func isSupportedAudioFile(at url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["m4a", "mp3", "wav", "caf"].contains(ext)
    }
    
    public func importAudio(from sourceURL: URL, destinationDirectory: URL) async throws -> (fileURL: URL, duration: TimeInterval, title: String) {
        let destURL = destinationDirectory.appendingPathComponent(sourceURL.lastPathComponent)
        let title = sourceURL.deletingPathExtension().lastPathComponent
        return (destURL, 180.0, title)
    }
}
