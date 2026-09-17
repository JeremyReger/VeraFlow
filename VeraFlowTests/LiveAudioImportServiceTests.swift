import Foundation
import Testing
@testable import VeraFlow

struct LiveAudioImportServiceTests {
    @Test("Imports wav, caf, and m4a into the folder and reads the duration", arguments: ["wav", "caf", "m4a"])
    func importsSupportedTypes(ext: String) async throws {
        let directory = try TestAudioFiles.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "Voice Memo 3.\(ext)")
        if ext == "m4a" {
            try TestAudioFiles.writeToneAAC(to: source, seconds: 2)
        } else {
            try TestAudioFiles.writeSilentCAF(to: source, seconds: 2)
        }
        let destination = directory.appending(path: "dest", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let imported = try await LiveAudioImportService().importAudio(from: source, into: destination)

        #expect(imported.fileName == "audio.\(ext)")
        #expect(abs(imported.duration - 2) < 0.2)
        #expect(FileManager.default.fileExists(at: destination.appending(path: "audio.\(ext)")))
        #expect(FileManager.default.fileExists(at: source), "The source is left in place; the caller decides about Inbox cleanup")
    }

    @Test("Rejects file types outside m4a/mp3/wav/caf")
    func rejectsUnsupportedType() async throws {
        let directory = try TestAudioFiles.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "notes.txt")
        try Data("hello".utf8).write(to: source)

        await #expect(throws: AudioImportError.unsupportedType("txt")) {
            try await LiveAudioImportService().importAudio(from: source, into: directory)
        }
    }

    @Test("A file that isn't really audio is rejected and the copy is removed")
    func rejectsGarbage() async throws {
        let directory = try TestAudioFiles.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "fake.mp3")
        try Data("not audio at all".utf8).write(to: source)
        let destination = directory.appending(path: "dest", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        await #expect(throws: AudioImportError.unreadable) {
            try await LiveAudioImportService().importAudio(from: source, into: destination)
        }
        #expect(!FileManager.default.fileExists(at: destination.appending(path: "audio.mp3")))
    }
}
