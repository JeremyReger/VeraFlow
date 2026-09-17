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

    /// Removes the row, its audio folder, and any queued pipeline work.
    func delete(_ recording: Recording) async throws {
        let id = recording.id
        await services.pipeline.cancel(recordingID: id)
        context.delete(recording)
        try context.save()
        try services.storage.deleteFolder(for: id)
    }

    /// Copies an audio file into a new recording's folder and queues it for processing.
    /// Files handed over by the share sheet land in the app's Inbox and are removed after import.
    @discardableResult
    func importAudio(from sourceURL: URL) async throws -> Recording {
        let id = UUID()
        let folder = try services.storage.folder(for: id)
        let imported: ImportedAudio
        do {
            imported = try await services.importer.importAudio(from: sourceURL, into: folder)
        } catch {
            try? services.storage.deleteFolder(for: id)
            throw error
        }

        let recording = Recording(
            id: id,
            title: Self.title(for: sourceURL),
            duration: imported.duration,
            audioFileName: imported.fileName,
            source: .imported,
            stage: .recorded
        )
        context.insert(recording)
        try context.save()
        await services.pipeline.enqueue(recordingID: id)

        if Self.isInboxURL(sourceURL) {
            try? FileManager.default.removeItem(at: sourceURL)
        }
        return recording
    }

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
