import Foundation
import Testing
@testable import VeraFlow

struct TemporaryFilesTests {
    @Test("Sweeping removes the contents of each folder, keeps the folders, and tolerates missing ones")
    func sweep() throws {
        let base = try TestAudioFiles.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let exports = base.appending(path: "Exports", directoryHint: .isDirectory)
        let inbox = base.appending(path: "Inbox", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        try Data("a".utf8).write(to: exports.appending(path: "notes.md"))
        try Data("b".utf8).write(to: exports.appending(path: "notes.pdf"))
        try Data("c".utf8).write(to: inbox.appending(path: "shared.m4a"))
        let missing = base.appending(path: "PhotoImports", directoryHint: .isDirectory)

        let removed = TemporaryFiles.sweep([exports, inbox, missing])

        #expect(removed == 3)
        #expect(try FileManager.default.contentsOfDirectory(atPath: exports.path).isEmpty)
        #expect(FileManager.default.fileExists(at: exports))
        #expect(FileManager.default.fileExists(at: inbox))
    }

    @Test("The app sweeps tmp/Exports, tmp/PhotoImports, and Documents/Inbox")
    func appDirectories() {
        let names = TemporaryFiles.appDefaultDirectories().map(\.lastPathComponent)
        #expect(names == ["Exports", "PhotoImports", "Inbox"])
    }
}
