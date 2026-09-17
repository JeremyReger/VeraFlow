import Foundation

/// A speaker as shown in exports.
struct ExportSpeaker: Sendable, Equatable {
    var key: String
    var displayName: String
}

/// A transcript paragraph as shown in exports.
struct ExportSegment: Sendable, Equatable {
    var start: TimeInterval
    var speakerKey: String?
    var text: String
}

/// Everything an export needs, detached from SwiftData so it can cross actor boundaries.
struct ExportDocument: Sendable, Equatable {
    var title: String
    var createdAt: Date
    var duration: TimeInterval
    var speakers: [ExportSpeaker]
    var summary: SummaryPayload?
    var segments: [ExportSegment]
    var includeTranscript: Bool

    /// Display name for a speaker key, falling back to the key itself.
    func speakerName(for key: String?) -> String {
        guard let key else { return "Speaker" }
        return speakers.first { $0.key == key }?.displayName ?? key
    }
}

/// What to send to Reminders.
struct ReminderRequest: Sendable, Equatable {
    var actionItem: ActionItem
    var recordingTitle: String
    var ownerDisplayName: String
}

/// A reminder list the user can pick.
struct ReminderList: Sendable, Equatable, Identifiable {
    var id: String
    var title: String
}

enum ExportError: Error, Equatable {
    case remindersAccessDenied
    case remindersFailed(String)
    case pdfFailed(String)
    case mailUnavailable
}

/// Builds exports and hands action items to Reminders (SPEC §12). Implemented for real in M6.
protocol ExportService: Sendable {
    func markdown(for document: ExportDocument) async -> String
    func plainText(for document: ExportDocument) async -> String
    func pdf(for document: ExportDocument) async throws -> Data
    /// File name per SPEC §12: `YYYY-MM-DD <Title>.<ext>`.
    func fileName(for document: ExportDocument, fileExtension: String) async -> String
    func reminderLists() async throws -> [ReminderList]
    /// Creates reminders and returns action item ID → reminder identifier.
    func createReminders(_ requests: [ReminderRequest], in list: ReminderList) async throws -> [UUID: String]
}

/// Produces minimal text output and records what it was asked to do.
actor FakeExportService: ExportService {
    var lists: [ReminderList] = [ReminderList(id: "default", title: "Reminders")]
    var errorToThrow: ExportError?
    private(set) var createdReminders: [ReminderRequest] = []

    func markdown(for document: ExportDocument) async -> String {
        var lines = ["# \(document.title)", ""]
        if let summary = document.summary {
            lines.append(summary.overview)
            lines.append("")
            for item in summary.actionItems {
                lines.append("- [ ] \(item.task)")
            }
        }
        if document.includeTranscript {
            lines.append("")
            for segment in document.segments {
                lines.append("**\(document.speakerName(for: segment.speakerKey))**: \(segment.text)")
            }
        }
        return lines.joined(separator: "\n")
    }

    func plainText(for document: ExportDocument) async -> String {
        await markdown(for: document)
            .replacingOccurrences(of: "# ", with: "")
            .replacingOccurrences(of: "**", with: "")
    }

    func pdf(for document: ExportDocument) async throws -> Data {
        if let errorToThrow { throw errorToThrow }
        return Data(await plainText(for: document).utf8)
    }

    func fileName(for document: ExportDocument, fileExtension: String) async -> String {
        let date = document.createdAt.formatted(.iso8601.year().month().day())
        return "\(date) \(document.title).\(fileExtension)"
    }

    func reminderLists() async throws -> [ReminderList] {
        if let errorToThrow { throw errorToThrow }
        return lists
    }

    func createReminders(_ requests: [ReminderRequest], in list: ReminderList) async throws -> [UUID: String] {
        if let errorToThrow { throw errorToThrow }
        createdReminders.append(contentsOf: requests)
        var ids: [UUID: String] = [:]
        for request in requests {
            ids[request.actionItem.id] = "fake-reminder-\(request.actionItem.id.uuidString)"
        }
        return ids
    }
}
