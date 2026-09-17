import Foundation

public protocol AudioImportServiceProtocol: Sendable {
    func isSupportedAudioFile(at url: URL) -> Bool
    func importAudio(from sourceURL: URL, destinationDirectory: URL) async throws -> (fileURL: URL, duration: TimeInterval, title: String)
}
