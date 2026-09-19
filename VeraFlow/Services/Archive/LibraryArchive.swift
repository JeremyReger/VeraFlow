import Foundation
import UniformTypeIdentifiers

/// What an archive says about itself.
struct ArchiveManifest: Codable, Sendable, Equatable {
    var formatVersion: Int
    var appVersion: String
    var createdAt: Date
    var recordingCount: Int
}

enum ArchiveError: Error, Equatable {
    /// The package was written by a newer VeraFlow.
    case newerFormat(Int)
    case notAnArchive
    case unreadable(String)
}

/// The `.veraflowarchive` package (v1.1 plan item 5): a folder Files shows as one item, holding
/// `manifest.json` and `recordings/<uuid>/` with `recording.json` and the audio file as stored.
/// Pure file work, no SwiftData; `LibraryActions` does the import and export around it.
enum LibraryArchive {
    static let formatVersion = 1
    static let pathExtension = "veraflowarchive"
    static let typeIdentifier = "com.jeremyreger.veraflow.archive"
    static let manifestName = "manifest.json"
    static let recordingsFolder = "recordings"
    static let recordingFileName = "recording.json"

    /// The exported type declared in `project.yml`; falls back to a folder type if the bundle
    /// lacks the declaration (tests).
    static var contentType: UTType {
        UTType(typeIdentifier) ?? .package
    }

    static func isArchive(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == pathExtension
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Writes the package at `packageURL` (replacing one already there). Audio is copied from
    /// `audioURLs[id]` when that file exists; a snapshot without audio is still written.
    /// `progress` runs 0...1 over the recordings.
    static func write(
        _ snapshots: [RecordingSnapshot],
        audioURLs: [UUID: URL],
        appVersion: String,
        to packageURL: URL,
        now: Date = .now,
        progress: (Double) -> Void = { _ in }
    ) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(at: packageURL) {
            try fileManager.removeItem(at: packageURL)
        }
        let recordingsURL = packageURL.appending(path: recordingsFolder, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: recordingsURL, withIntermediateDirectories: true)
        let manifest = ArchiveManifest(formatVersion: formatVersion, appVersion: appVersion, createdAt: now, recordingCount: snapshots.count)
        try encoder.encode(manifest).write(to: packageURL.appending(path: manifestName), options: .atomic)
        for (index, snapshot) in snapshots.enumerated() {
            if Task.isCancelled { throw CancellationError() }
            let folder = recordingsURL.appending(path: snapshot.id.uuidString, directoryHint: .isDirectory)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try encoder.encode(snapshot).write(to: folder.appending(path: recordingFileName), options: .atomic)
            if let audio = audioURLs[snapshot.id], fileManager.fileExists(at: audio) {
                try fileManager.copyItem(at: audio, to: folder.appending(path: snapshot.audioFileName))
            }
            progress(Double(index + 1) / Double(max(1, snapshots.count)))
        }
    }

    /// Reads the manifest and every recording in the package. Audio stays where it is; use
    /// `audioURL(in:for:)` to copy it.
    static func read(_ packageURL: URL) throws -> (manifest: ArchiveManifest, snapshots: [RecordingSnapshot]) {
        let fileManager = FileManager.default
        let manifestURL = packageURL.appending(path: manifestName)
        guard fileManager.fileExists(at: manifestURL) else { throw ArchiveError.notAnArchive }
        let manifest: ArchiveManifest
        do {
            manifest = try decoder.decode(ArchiveManifest.self, from: Data(contentsOf: manifestURL))
        } catch {
            throw ArchiveError.unreadable("manifest: \(error.localizedDescription)")
        }
        guard manifest.formatVersion <= formatVersion else { throw ArchiveError.newerFormat(manifest.formatVersion) }
        let recordingsURL = packageURL.appending(path: recordingsFolder, directoryHint: .isDirectory)
        let folders = (try? fileManager.contentsOfDirectory(at: recordingsURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        var snapshots: [RecordingSnapshot] = []
        for folder in folders {
            let file = folder.appending(path: recordingFileName)
            guard fileManager.fileExists(at: file) else { continue }
            do {
                snapshots.append(try decoder.decode(RecordingSnapshot.self, from: Data(contentsOf: file)))
            } catch {
                throw ArchiveError.unreadable("\(folder.lastPathComponent): \(error.localizedDescription)")
            }
        }
        snapshots.sort { $0.createdAt < $1.createdAt }
        return (manifest, snapshots)
    }

    /// The audio file for a snapshot inside the package, if it was included.
    static func audioURL(in packageURL: URL, for snapshot: RecordingSnapshot) -> URL? {
        let url = packageURL
            .appending(path: recordingsFolder, directoryHint: .isDirectory)
            .appending(path: snapshot.id.uuidString, directoryHint: .isDirectory)
            .appending(path: snapshot.audioFileName)
        return FileManager.default.fileExists(at: url) ? url : nil
    }

    /// `2026-09-19 VeraFlow library.veraflowarchive` or `2026-09-19 <Title>.veraflowarchive`.
    static func packageName(for title: String, createdAt: Date, calendar: Calendar = .current) -> String {
        let document = ExportDocument(title: title, createdAt: createdAt, duration: 0, speakers: [], summary: nil, segments: [], includeTranscript: false)
        return ExportRenderer.fileName(for: document, fileExtension: pathExtension, calendar: calendar)
    }
}

/// What an import did.
struct ArchiveImportOutcome: Equatable, Sendable {
    var importedIDs: [UUID] = []
    var skippedIDs: [UUID] = []
    var missingAudioIDs: [UUID] = []

    var userMessage: String {
        var parts: [String] = []
        parts.append(importedIDs.count == 1 ? "Imported 1 recording." : "Imported \(importedIDs.count) recordings.")
        if !skippedIDs.isEmpty {
            parts.append(skippedIDs.count == 1 ? "1 was already in your Library." : "\(skippedIDs.count) were already in your Library.")
        }
        if !missingAudioIDs.isEmpty {
            parts.append(missingAudioIDs.count == 1 ? "1 came without its audio." : "\(missingAudioIDs.count) came without their audio.")
        }
        return parts.joined(separator: " ")
    }
}
