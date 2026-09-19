import Foundation
import SwiftData
import Testing
@testable import VeraFlow

/// SwiftUI sets an alert's `isPresented` binding to false (our cancel path) before it runs the
/// tapped button's action. The controller must survive that ordering.
@MainActor
struct RecordingActionsControllerTests {
    private struct Harness {
        let container: ModelContainer
        let context: ModelContext
        let storage: RecordingStorage
        let controller: RecordingActionsController

        func cleanUp() {
            try? FileManager.default.removeItem(at: storage.rootDirectory)
        }
    }

    private func makeHarness() throws -> Harness {
        let storage = RecordingStorage(rootDirectory: try TestAudioFiles.temporaryDirectory())
        let services = AppServices.fakes(storage: storage)
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let controller = RecordingActionsController(actions: LibraryActions(context: context, services: services))
        return Harness(container: container, context: context, storage: storage, controller: controller)
    }

    @Test("Rename still applies when the alert is dismissed before Save runs")
    func renameSurvivesDismissFirst() throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let recording = Recording(title: "Kitchen remodel walk-through", createdAt: .now, stage: .recorded)
        harness.context.insert(recording)
        try harness.context.save()

        let controller = harness.controller
        controller.beginRename(recording)
        #expect(controller.renameTarget === recording)
        #expect(controller.renameDraft == "Kitchen remodel walk-through")

        controller.renameDraft = "Kitchen remodel walk-through edited"
        controller.cancelRename()          // what the isPresented binding does on dismiss
        controller.commitRename(recording) // then the Save action

        #expect(recording.title == "Kitchen remodel walk-through edited")
        #expect(controller.renameTarget == nil)
        #expect(controller.errorMessage == nil)
    }

    @Test("Delete still applies when the dialog is dismissed before Delete runs, and it moves the recording to Recently Deleted")
    func deleteSurvivesDismissFirst() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let recording = Recording(title: "Meeting", createdAt: .now, stage: .recorded)
        harness.context.insert(recording)
        try harness.context.save()
        try harness.storage.folder(for: recording.id)

        let controller = harness.controller
        var deletedID: UUID?
        controller.onDeleted = { deletedID = $0.id }
        controller.requestDelete(recording)
        controller.deleteTarget = nil              // dismissal
        await controller.confirmDelete(recording)  // then the action

        #expect(deletedID == recording.id)
        // v1.1: the row and audio stay for 30 days in Recently Deleted (plan item 10).
        #expect(try harness.context.fetchCount(FetchDescriptor<Recording>()) == 1)
        #expect(recording.isTrashed)
        #expect(try harness.storage.existingFolderIDs() == [recording.id])
    }

    @Test("An empty title is refused with a message and the old title stays")
    func emptyTitleRefused() throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let recording = Recording(title: "Meeting", createdAt: .now, stage: .recorded)
        harness.context.insert(recording)
        try harness.context.save()

        let controller = harness.controller
        controller.beginRename(recording)
        controller.renameDraft = "   "
        controller.commitRename(recording)

        #expect(recording.title == "Meeting")
        #expect(controller.errorMessage == "A recording needs a title.")
    }
}
