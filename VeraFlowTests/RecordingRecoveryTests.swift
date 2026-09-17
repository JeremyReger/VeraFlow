import Foundation
import SwiftData
import Testing
@testable import VeraFlow

@MainActor
struct RecordingRecoveryTests {
    /// The container must outlive the context; the context does not retain it.
    @MainActor
    private struct Store {
        let container: ModelContainer
        var context: ModelContext { container.mainContext }
    }

    private func makeStore() throws -> Store {
        Store(container: try ModelContainerFactory.makeInMemory())
    }

    private func makeStorage() throws -> RecordingStorage {
        RecordingStorage(rootDirectory: try TestAudioFiles.temporaryDirectory())
    }

    @Test("Interrupted recordings with a readable file become .recorded with the file's duration")
    func recoversReadableFile() throws {
        let store = try makeStore()
        let context = store.context
        let storage = try makeStorage()
        defer { try? FileManager.default.removeItem(at: storage.rootDirectory) }

        let interrupted = Recording(title: "Crashed", stage: .recording)
        let finished = Recording(title: "Fine", duration: 10, stage: .ready)
        context.insert(interrupted)
        context.insert(finished)
        try context.save()

        var recovery = RecordingRecovery(context: context, storage: storage)
        recovery.durationReader = { _ in 42 }
        let outcome = try recovery.run()

        #expect(outcome.recoveredIDs == [interrupted.id])
        #expect(outcome.unrecoverableIDs.isEmpty)
        #expect(interrupted.stage == .recorded)
        #expect(interrupted.duration == 42)
        #expect(finished.stage == .ready)
        #expect(finished.duration == 10)
        #expect(outcome.userMessage == "Recovered an interrupted recording. It's ready in your Library.")
    }

    @Test("Interrupted recordings with a missing file are marked failed")
    func marksMissingFileFailed() throws {
        let store = try makeStore()
        let context = store.context
        let storage = try makeStorage()
        defer { try? FileManager.default.removeItem(at: storage.rootDirectory) }

        let interrupted = Recording(title: "Crashed", stage: .recording)
        context.insert(interrupted)
        try context.save()

        let outcome = try RecordingRecovery(context: context, storage: storage).run()

        #expect(outcome.recoveredIDs.isEmpty)
        #expect(outcome.unrecoverableIDs == [interrupted.id])
        #expect(interrupted.stage == .failed)
        #expect(interrupted.failureMessage == RecordingRecovery.unrecoverableMessage)
        #expect(outcome.userMessage == "A recording was interrupted and its audio could not be recovered.")
    }

    @Test("Real CAF file on disk is recovered end to end")
    func recoversRealFile() throws {
        let store = try makeStore()
        let context = store.context
        let storage = try makeStorage()
        defer { try? FileManager.default.removeItem(at: storage.rootDirectory) }

        let interrupted = Recording(title: "Crashed", stage: .recording)
        context.insert(interrupted)
        try context.save()
        try storage.folder(for: interrupted.id)
        try TestAudioFiles.writeSilentCAF(
            to: storage.audioURL(for: interrupted.id, fileName: interrupted.audioFileName),
            seconds: 3
        )

        let outcome = try RecordingRecovery(context: context, storage: storage).run()
        #expect(outcome.recoveredIDs == [interrupted.id])
        #expect(interrupted.stage == .recorded)
        #expect(abs(interrupted.duration - 3) < 0.001)
    }

    @Test("A force-quit recording (truncated ADTS file) is recovered as playable")
    func recoversTruncatedADTS() throws {
        let store = try makeStore()
        let context = store.context
        let storage = try makeStorage()
        defer { try? FileManager.default.removeItem(at: storage.rootDirectory) }

        let interrupted = Recording(title: "Killed", stage: .recording)
        #expect(interrupted.audioFileName == "audio.aac")
        context.insert(interrupted)
        try context.save()
        try storage.folder(for: interrupted.id)
        let url = storage.audioURL(for: interrupted.id, fileName: interrupted.audioFileName)
        try TestAudioFiles.writeToneAAC(to: url, seconds: 3)
        let data = try Data(contentsOf: url)
        try data.prefix(data.count / 2).write(to: url)

        let outcome = try RecordingRecovery(context: context, storage: storage).run()
        #expect(outcome.recoveredIDs == [interrupted.id])
        #expect(interrupted.stage == .recorded)
        #expect(interrupted.duration > 0.5)
    }

    @Test("Nothing to recover leaves the store untouched and no message")
    func nothingToRecover() throws {
        let store = try makeStore()
        let context = store.context
        let storage = try makeStorage()
        defer { try? FileManager.default.removeItem(at: storage.rootDirectory) }
        context.insert(Recording(title: "Fine", stage: .ready))
        try context.save()

        let outcome = try RecordingRecovery(context: context, storage: storage).run()
        #expect(outcome.isEmpty)
        #expect(outcome.userMessage == nil)
    }

    @Test("AppState runs recovery on startup and surfaces the message")
    func appStateRunsRecovery() async throws {
        let store = try makeStore()
        let context = store.context
        let storage = try makeStorage()
        defer { try? FileManager.default.removeItem(at: storage.rootDirectory) }
        context.insert(Recording(title: "Crashed", stage: .recording))
        try context.save()

        let state = AppState(services: .fakes(storage: storage), modelContext: context)
        await state.startup()

        #expect(state.lastRecovery?.unrecoverableIDs.count == 1)
        #expect(state.recoveryMessage != nil)
        state.dismissRecoveryMessage()
        #expect(state.recoveryMessage == nil)
    }
}
