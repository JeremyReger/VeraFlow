import Foundation
import SwiftData

enum LibraryActionError: Error, Equatable {
    case emptyTitle
}

/// Rename, delete, favorite, tag, and import, against the SwiftData store (SPEC §3, M2).
/// Views call these; tests drive them with an in-memory container and fakes.
@MainActor
struct LibraryActions {
    let context: ModelContext
    let services: AppServices

    /// Title is trimmed; an empty result is rejected so a recording never loses its name.
    func rename(_ recording: Recording, to title: String) throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LibraryActionError.emptyTitle }
        recording.title = trimmed
        try context.save()
    }

    func toggleFavorite(_ recording: Recording) throws {
        recording.isFavorite.toggle()
        try context.save()
    }

    /// Tags are trimmed, de-duplicated (case-insensitively, first spelling wins), and emptied of blanks.
    func setTags(_ recording: Recording, to tags: [String]) throws {
        recording.tags = Self.normalized(tags)
        try context.save()
    }

    static func normalized(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in tags {
            let tag = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tag.isEmpty, seen.insert(tag.lowercased()).inserted else { continue }
            result.append(tag)
        }
        return result
    }

    /// Moves the recording to Recently Deleted (v1.1 plan item 10): the row and audio stay for
    /// `TrashPolicy.retention`, queued work is cancelled, and the Library hides it.
    func trash(_ recording: Recording, now: Date = .now) async throws {
        await services.pipeline.cancel(recordingID: recording.id)
        recording.deletedAt = now
        try context.save()
    }

    /// Back from Recently Deleted; processing that was cut short is queued again.
    func restore(_ recording: Recording) async throws {
        recording.deletedAt = nil
        try context.save()
        if LivePipelineCoordinator.needsWork(recording.stage) {
            await services.pipeline.enqueue(recordingID: recording.id)
        }
    }

    /// Removes the row, its audio folder, and any queued pipeline work, for good.
    func delete(_ recording: Recording) async throws {
        let id = recording.id
        await services.pipeline.cancel(recordingID: id)
        context.delete(recording)
        try context.save()
        try services.storage.deleteFolder(for: id)
    }

    /// Everything in Recently Deleted, for good.
    func emptyTrash() async throws {
        let trashed = try context.fetch(FetchDescriptor<Recording>()).filter(\.isTrashed)
        for recording in trashed {
            try await delete(recording)
        }
    }

    /// "Delete all data" (SPEC §14.4): every row, every audio folder (orphans included), and any queued work.
    func deleteAll() async throws {
        let recordings = try context.fetch(FetchDescriptor<Recording>())
        for recording in recordings {
            await services.pipeline.cancel(recordingID: recording.id)
            context.delete(recording)
        }
        try context.save()
        for id in try services.storage.existingFolderIDs() {
            try services.storage.deleteFolder(for: id)
        }
    }

    /// Copies an audio file into a new recording's folder and queues it for processing.
    /// Files handed over by the share sheet land in the app's Inbox and are removed after import.
    @discardableResult
    func importAudio(from sourceURL: URL) async throws -> Recording {
        let id = UUID()
        let folder = try services.storage.folder(for: id, excludeFromBackup: !AppPreferences.includesRecordingsInBackup())
        let imported: ImportedAudio
        do {
            imported = try await services.importer.importAudio(from: sourceURL, into: folder)
        } catch {
            try? services.storage.deleteFolder(for: id)
            if Self.isInboxURL(sourceURL) {
                // Nothing to keep: a rejected file shouldn't sit in Documents/Inbox (S-7).
                try? FileManager.default.removeItem(at: sourceURL)
            }
            throw error
        }

        let recording = Recording(
            id: id,
            title: Self.title(for: sourceURL),
            duration: imported.duration,
            audioFileName: imported.fileName,
            source: .imported,
            stage: .recorded,
            localeIdentifier: AppPreferences.effectiveTranscriptionLocale().identifier(.bcp47)
        )
        context.insert(recording)
        try context.save()
        await services.pipeline.enqueue(recordingID: id)

        if Self.isInboxURL(sourceURL) {
            try? FileManager.default.removeItem(at: sourceURL)
        }
        return recording
    }

    /// "Transcribe again in…" (v1.1 plan item 8): the transcript, speaker labels and summaries
    /// are replaced by a fresh run in `locale`; marks, tags and the title stay.
    func retranscribe(_ recording: Recording, in locale: Locale) async throws {
        await services.pipeline.cancel(recordingID: recording.id)
        for segment in recording.segments { context.delete(segment) }
        for speaker in recording.speakers { context.delete(speaker) }
        for summary in recording.summaries { context.delete(summary) }
        recording.segments = []
        recording.speakers = []
        recording.summaries = []
        recording.localeIdentifier = locale.identifier(.bcp47)
        recording.transcriptionEngine = nil
        recording.stage = .recorded
        recording.failedStage = nil
        recording.failureMessage = nil
        try context.save()
        await services.pipeline.enqueue(recordingID: recording.id)
    }

    // MARK: Archive (v1.1 plan item 5)

    /// Writes the recordings (Recently Deleted excluded) as a `.veraflowarchive` package at
    /// `destination`, audio included. Runs the file work off the main actor.
    func exportArchive(_ recordings: [Recording], to destination: URL, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        let live = recordings.filter { !$0.isTrashed }
        let snapshots = live.map { RecordingSnapshot(recording: $0) }
        var audioURLs: [UUID: URL] = [:]
        for recording in live where recording.audioAvailable {
            audioURLs[recording.id] = services.storage.audioURL(for: recording.id, fileName: recording.audioFileName)
        }
        let urls = audioURLs
        let version = AppInfo.versionString
        try await Task.detached(priority: .userInitiated) {
            try LibraryArchive.write(snapshots, audioURLs: urls, appVersion: version, to: destination, progress: progress)
        }.value
    }

    /// Reads a package and inserts its recordings. Ones already in the Library are skipped unless
    /// `replace` is set. Audio is copied into the recording's folder; a snapshot without audio is
    /// still imported with `audioAvailable` off (its transcript and summary stay usable).
    @discardableResult
    func importArchive(from packageURL: URL, replace: Bool = false, source: RecordingSource? = nil, extraTags: [String] = []) async throws -> ArchiveImportOutcome {
        let isScoped = packageURL.startAccessingSecurityScopedResource()
        defer {
            if isScoped { packageURL.stopAccessingSecurityScopedResource() }
        }
        let (_, snapshots) = try LibraryArchive.read(packageURL)
        var outcome = ArchiveImportOutcome()
        let existingIDs = Set(try context.fetch(FetchDescriptor<Recording>()).map(\.id))
        for snapshot in snapshots {
            if existingIDs.contains(snapshot.id) {
                guard replace, let existing = try context.fetch(FetchDescriptor<Recording>()).first(where: { $0.id == snapshot.id }) else {
                    outcome.skippedIDs.append(snapshot.id)
                    continue
                }
                try await delete(existing)
            }
            let folder = try services.storage.folder(for: snapshot.id, excludeFromBackup: !AppPreferences.includesRecordingsInBackup())
            let recording = snapshot.makeRecording(source: source, extraTags: extraTags)
            if let audio = LibraryArchive.audioURL(in: packageURL, for: snapshot) {
                let destination = folder.appending(path: snapshot.audioFileName)
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.copyItem(at: audio, to: destination)
                try? FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                    ofItemAtPath: destination.path(percentEncoded: false)
                )
                recording.audioAvailable = true
            } else {
                recording.audioAvailable = false
                outcome.missingAudioIDs.append(snapshot.id)
                if LivePipelineCoordinator.needsWork(recording.stage) || recording.stage == .recording {
                    // Nothing can transcribe it; keep whatever text came along.
                    recording.stage = recording.segments.isEmpty ? .failed : .ready
                    recording.failureMessage = recording.segments.isEmpty ? Self.missingAudioMessage : nil
                }
            }
            context.insert(recording)
            outcome.importedIDs.append(recording.id)
        }
        try context.save()
        for id in outcome.importedIDs {
            if let recording = try context.fetch(FetchDescriptor<Recording>()).first(where: { $0.id == id }),
               recording.audioAvailable, LivePipelineCoordinator.needsWork(recording.stage) {
                await services.pipeline.enqueue(recordingID: id)
            }
        }
        if Self.isInboxURL(packageURL) {
            try? FileManager.default.removeItem(at: packageURL)
        }
        return outcome
    }

    static let missingAudioMessage = "The archive didn't include this recording's audio."

    /// "Voice Memo 3.m4a" → "Voice Memo 3"; falls back to the dated default.
    static func title(for url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? Recording.suggestedTitle() : name
    }

    static func isInboxURL(_ url: URL) -> Bool {
        url.pathComponents.contains("Inbox")
    }
}
