import Foundation
import Testing
@testable import VeraFlow

struct DataProtectionTests {
    @Test("Store files are found with their -wal and -shm siblings and excluded from backup")
    func storeFilesAndExclusion() throws {
        let base = try TestAudioFiles.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let store = base.appending(path: "default.store")
        try Data("s".utf8).write(to: store)
        try Data("w".utf8).write(to: URL(filePath: store.path + "-wal"))

        let files = DataProtection.storeFiles(for: store)
        #expect(files.map(\.lastPathComponent) == ["default.store", "default.store-wal"], "the missing -shm is skipped")

        DataProtection.apply(to: files)
        for file in files {
            #expect(DataProtection.isExcludedFromBackup(file))
        }
    }
}
