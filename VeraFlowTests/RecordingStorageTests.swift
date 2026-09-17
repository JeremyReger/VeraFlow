import Foundation
import Testing
@testable import VeraFlow

struct RecordingStorageTests {
    private func makeStorage() -> RecordingStorage {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "VeraFlowTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        return RecordingStorage(rootDirectory: root)
    }

    @Test("Creates one folder per recording and lists it back")
    func createsAndListsFolders() throws {
        let storage = makeStorage()
        defer { try? FileManager.default.removeItem(at: storage.rootDirectory) }

        let id = UUID()
        let folder = try storage.folder(for: id)
        #expect(FileManager.default.fileExists(at: folder))
        #expect(folder.lastPathComponent == id.uuidString)
        #expect(try storage.existingFolderIDs() == [id])

        let audio = storage.audioURL(for: id, fileName: "audio.caf")
        #expect(audio.deletingLastPathComponent() == folder)
        #expect(audio.lastPathComponent == "audio.caf")
    }

    @Test("Folder creation is idempotent")
    func folderIsIdempotent() throws {
        let storage = makeStorage()
        defer { try? FileManager.default.removeItem(at: storage.rootDirectory) }

        let id = UUID()
        let first = try storage.folder(for: id)
        let second = try storage.folder(for: id)
        #expect(first == second)
        #expect(try storage.existingFolderIDs().count == 1)
    }

    @Test("Deleting removes the folder; deleting again is a no-op")
    func deleteFolder() throws {
        let storage = makeStorage()
        defer { try? FileManager.default.removeItem(at: storage.rootDirectory) }

        let id = UUID()
        try storage.folder(for: id)
        try storage.deleteFolder(for: id)
        #expect(try storage.existingFolderIDs().isEmpty)
        try storage.deleteFolder(for: id)
    }

    @Test("Backup exclusion is applied to new folders")
    func backupExclusion() throws {
        let storage = makeStorage()
        defer { try? FileManager.default.removeItem(at: storage.rootDirectory) }

        let folder = try storage.folder(for: UUID(), excludeFromBackup: true)
        let values = try folder.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test("Unknown entries in the root are ignored")
    func ignoresNonUUIDEntries() throws {
        let storage = makeStorage()
        defer { try? FileManager.default.removeItem(at: storage.rootDirectory) }

        try storage.folder(for: UUID())
        let stray = storage.rootDirectory.appending(path: "not-a-uuid", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: stray, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: storage.rootDirectory.appending(path: "notes.txt"))
        #expect(try storage.existingFolderIDs().count == 1)
    }

    @Test("Works when the root path contains spaces, like Application Support on device")
    func rootPathWithSpaces() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "Space Test \(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "Recordings", directoryHint: .isDirectory)
        let storage = RecordingStorage(rootDirectory: root)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let id = UUID()
        try storage.folder(for: id)
        let audio = storage.audioURL(for: id, fileName: "audio.caf")
        try Data("x".utf8).write(to: audio)

        #expect(FileManager.default.fileExists(at: audio))
        #expect(try storage.existingFolderIDs() == [id])

        try storage.deleteFolder(for: id)
        #expect(!FileManager.default.fileExists(at: audio))
        #expect(try storage.existingFolderIDs().isEmpty)
    }
}
