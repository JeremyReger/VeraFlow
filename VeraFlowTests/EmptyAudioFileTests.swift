import Foundation
import Testing
@testable import VeraFlow

/// A capture that wrote nothing used to reach the transcription step and fail there with a Core
/// Audio error number (Jeremy's first Mac recording, 2026-09-19). Both ends now say what happened.
struct EmptyAudioFileTests {
    private func temporaryFile(bytes: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "empty-audio-\(UUID().uuidString).aac", directoryHint: .notDirectory)
        try Data(repeating: 0, count: bytes).write(to: url)
        return url
    }

    @Test("A zero-byte file reads as empty, a file with bytes does not")
    func size() throws {
        let empty = try temporaryFile(bytes: 0)
        defer { try? FileManager.default.removeItem(at: empty) }
        #expect(AudioFileInfo.isEmpty(at: empty))

        let written = try temporaryFile(bytes: 64)
        defer { try? FileManager.default.removeItem(at: written) }
        #expect(!AudioFileInfo.isEmpty(at: written))
    }

    @Test("A file that was never created reads as empty rather than throwing")
    func missing() {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "no-such-file-\(UUID().uuidString).aac", directoryHint: .notDirectory)
        #expect(AudioFileInfo.isEmpty(at: url))
    }

    @Test("A path with spaces and accents is measured, not mangled")
    func awkwardPath() throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "Räumliche Notizen \(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "audio.aac", directoryHint: .notDirectory)
        try Data(repeating: 0, count: 8).write(to: url)
        #expect(!AudioFileInfo.isEmpty(at: url))
    }
}
