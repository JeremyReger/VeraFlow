import Foundation

public enum ExportFormat: String, Sendable, CaseIterable {
    case markdown
    case pdf
    case plainText
    case emailDraft
    case reminders
    case audioM4A
}

@MainActor
public protocol ExportServiceProtocol: Sendable {
    func exportMarkdown(recording: Recording, includeTranscript: Bool) -> String
    func exportPlainText(recording: Recording, includeTranscript: Bool) -> String
    func exportPDFData(recording: Recording, includeTranscript: Bool) async throws -> Data
    func exportActionItemsToReminders(actionItems: [ActionItem], listTitle: String?) async throws -> [String]
    func exportAudioM4A(recording: Recording, sourceAudioURL: URL, outputURL: URL) async throws
}
