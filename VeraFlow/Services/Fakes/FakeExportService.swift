import Foundation

public final class FakeExportService: ExportServiceProtocol, Sendable {
    public init() {}
    
    public func exportMarkdown(recording: Recording, includeTranscript: Bool) -> String {
        var md = "# \(recording.title)\n\n"
        md += "- **Date:** \(recording.createdAt.formatted())\n"
        md += "- **Duration:** \(Int(recording.duration)) seconds\n\n"
        md += "## Summary\n\nPlaceholder summary content.\n\n"
        if includeTranscript {
            md += "## Transcript\n\n"
            for segment in recording.segments {
                md += "**\(segment.speakerKey ?? "Speaker"):** \(segment.text)\n\n"
            }
        }
        return md
    }
    
    public func exportPlainText(recording: Recording, includeTranscript: Bool) -> String {
        var text = "\(recording.title)\n\n"
        text += "Date: \(recording.createdAt.formatted())\n"
        text += "Duration: \(Int(recording.duration))s\n\n"
        if includeTranscript {
            text += "Transcript:\n"
            for segment in recording.segments {
                text += "\(segment.speakerKey ?? "Speaker"): \(segment.text)\n"
            }
        }
        return text
    }
    
    public func exportPDFData(recording: Recording, includeTranscript: Bool) async throws -> Data {
        let text = exportPlainText(recording: recording, includeTranscript: includeTranscript)
        return text.data(using: .utf8) ?? Data()
    }
    
    public func exportActionItemsToReminders(actionItems: [ActionItem], listTitle: String?) async throws -> [String] {
        return actionItems.map { _ in UUID().uuidString }
    }
    
    public func exportAudioM4A(recording: Recording, sourceAudioURL: URL, outputURL: URL) async throws {
        // Fake export copies or creates empty placeholder
        try "fake audio".write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
