import Foundation
import SwiftData
import Testing
@testable import VeraFlow

@MainActor
struct DeleteAllDataTests {
    @Test("Delete all removes every row, every folder (orphans too), and cancels queued work")
    func deleteAll() async throws {
        let storage = RecordingStorage(rootDirectory: try TestAudioFiles.temporaryDirectory())
        defer { try? FileManager.default.removeItem(at: storage.rootDirectory) }
        let container = try ModelContainerFactory.makeInMemory()
        let pipeline = FakePipelineCoordinator()
        var services = AppServices.fakes(storage: storage)
        services.pipeline = pipeline

        let first = Recording(title: "one", stage: .ready)
        let second = Recording(title: "two", stage: .transcribing)
        container.mainContext.insert(first)
        container.mainContext.insert(second)
        try container.mainContext.save()
        try storage.folder(for: first.id)
        try storage.folder(for: second.id)
        let orphan = UUID()
        try storage.folder(for: orphan)

        try await LibraryActions(context: container.mainContext, services: services).deleteAll()

        #expect(try container.mainContext.fetch(FetchDescriptor<Recording>()).isEmpty)
        #expect(try storage.existingFolderIDs().isEmpty)
        #expect(Set(await pipeline.cancelled) == [first.id, second.id])
    }
}
