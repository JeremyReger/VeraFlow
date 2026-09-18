import Foundation

/// Markdown and plain-text renderings of a recording (SPEC §12). Pure Swift, unit-tested; the
/// PDF is laid out from the plain-text sections by `LiveExportService`.
enum ExportRenderer {
    /// One block of an export: a heading and its lines.
    struct Section: Equatable, Sendable {
        var heading: String
        var lines: [String]
    }

    static func markdown(for document: ExportDocument) -> String {
        var out: [String] = ["# \(document.title)", "", metadataLine(document), ""]
        if !document.speakers.isEmpty {
            out.append("Speakers: " + document.speakers.map(\.displayName).joined(separator: ", "))
            out.append("")
        }
        for section in summarySections(document) {
            out.append("## \(section.heading)")
            out.append("")
            out.append(contentsOf: section.lines)
            out.append("")
        }
        if let summary = document.summary, !summary.actionItems.isEmpty {
            out.append("## Action items")
            out.append("")
            out.append(contentsOf: summary.actionItems.map { "- [ ] " + actionItemLine($0, document: document) })
            out.append("")
        }
        if case .walkthrough(let summary)? = document.summary, summary.areas.contains(where: { !$0.measurements.isEmpty }) {
            out.append("> Check measurements against the audio before quoting.")
            out.append("")
        }
        if document.includeTranscript, !document.segments.isEmpty {
            out.append("## Transcript")
            out.append("")
            for segment in document.segments {
                out.append("**[\(TranscriptChunker.timestamp(segment.start))] \(document.speakerName(for: segment.speakerKey)):** \(segment.text)")
                out.append("")
            }
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n"
    }

    static func plainText(for document: ExportDocument) -> String {
        var out: [String] = [document.title.uppercased(), metadataLine(document), ""]
        if !document.speakers.isEmpty {
            out.append("Speakers: " + document.speakers.map(\.displayName).joined(separator: ", "))
            out.append("")
        }
        for section in summarySections(document) {
            out.append(section.heading.uppercased())
            out.append(contentsOf: section.lines.map { $0.hasPrefix("- ") ? "• " + String($0.dropFirst(2)) : $0 })
            out.append("")
        }
        if let summary = document.summary, !summary.actionItems.isEmpty {
            out.append("ACTION ITEMS")
            out.append(contentsOf: summary.actionItems.map { "☐ " + actionItemLine($0, document: document) })
            out.append("")
        }
        if case .walkthrough(let summary)? = document.summary, summary.areas.contains(where: { !$0.measurements.isEmpty }) {
            out.append("Check measurements against the audio before quoting.")
            out.append("")
        }
        if document.includeTranscript, !document.segments.isEmpty {
            out.append("TRANSCRIPT")
            for segment in document.segments {
                out.append("[\(TranscriptChunker.timestamp(segment.start))] \(document.speakerName(for: segment.speakerKey)): \(segment.text)")
            }
            out.append("")
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n"
    }

    /// Summary only (for Copy).
    static func summaryText(for document: ExportDocument) -> String {
        var copy = document
        copy.includeTranscript = false
        return plainText(for: copy)
    }

    /// Action items only (for Copy), one per line.
    static func actionItemsText(for document: ExportDocument) -> String {
        guard let summary = document.summary else { return "" }
        return summary.actionItems.map { "☐ " + actionItemLine($0, document: document) }.joined(separator: "\n")
    }

    /// Body for an email that isn't the client follow-up: summary + action items.
    static func emailBody(for document: ExportDocument) -> String {
        summaryText(for: document)
    }

    /// `2026-09-17 Kitchen remodel walk-through.md`, with characters a file system rejects removed.
    static func fileName(for document: ExportDocument, fileExtension: String, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: document.createdAt)
        let date = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        var title = document.title
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { title = "Recording" }
        return "\(date) \(title.prefix(80)).\(fileExtension)"
    }

    /// Notes for a reminder: owner + "From: <recording title> @ mm:ss" (SPEC §12).
    static func reminderNotes(for request: ReminderRequest) -> String {
        var lines: [String] = []
        if !request.ownerDisplayName.isEmpty {
            lines.append("Owner: \(request.ownerDisplayName)")
        }
        var source = "From: \(request.recordingTitle)"
        if let timestamp = request.actionItem.timestamp {
            source += " @ \(TranscriptChunker.timestamp(timestamp))"
        }
        lines.append(source)
        if !request.actionItem.dueText.isEmpty {
            lines.append("Due as spoken: \(request.actionItem.dueText)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Sections

    static func summarySections(_ document: ExportDocument) -> [Section] {
        guard let summary = document.summary else { return [] }
        var sections: [Section] = []
        func add(_ heading: String, _ items: [String]) {
            guard !items.isEmpty else { return }
            sections.append(Section(heading: heading, lines: items.map { "- \($0)" }))
        }
        switch summary {
        case .general(let general):
            sections.append(Section(heading: "Summary", lines: [general.overview]))
            add("Key points", general.keyPoints)
            add("Decisions", general.decisions)
            add("Open questions", general.openQuestions)
        case .client(let client):
            sections.append(Section(heading: "Summary", lines: [client.overview]))
            add("Client goals", client.clientGoals)
            add("Concerns", client.concerns)
            add("Decisions", client.decisions)
            if !client.nextMeeting.isEmpty {
                sections.append(Section(heading: "Next meeting", lines: [client.nextMeeting]))
            }
            add("Open questions", client.openQuestions)
        case .walkthrough(let walkthrough):
            var overview = [walkthrough.overview]
            if !walkthrough.location.isEmpty { overview.insert("Location: \(walkthrough.location)", at: 0) }
            sections.append(Section(heading: "Summary", lines: overview))
            for area in walkthrough.areas {
                var lines = area.tasks.map { "- \($0)" }
                lines += area.measurements.map { measurement in
                    var line = "- \(measurement.item): \(measurement.value)"
                    if let timestamp = measurement.timestamp { line += " (@ \(TranscriptChunker.timestamp(timestamp)))" }
                    return line
                }
                lines += area.materials.map { material in
                    let extra = [material.quantity, material.notes].filter { !$0.isEmpty }.joined(separator: ", ")
                    return "- Material: \(material.name)" + (extra.isEmpty ? "" : " (\(extra))")
                }
                if !lines.isEmpty { sections.append(Section(heading: area.name, lines: lines)) }
            }
            add("Customer requests", walkthrough.customerRequests)
            add("Issues found", walkthrough.issuesFound)
            add("Quote notes", walkthrough.quoteNotes)
        }
        return sections
    }

    static func actionItemLine(_ item: ActionItem, document: ExportDocument) -> String {
        var line = item.task
        var details: [String] = []
        let owner = item.ownerSpeakerKey.map { document.speakerName(for: $0) } ?? item.owner
        if !owner.isEmpty { details.append(owner) }
        if let dueDate = item.dueDate {
            details.append("due " + dueDate.formatted(date: .abbreviated, time: .omitted))
        } else if !item.dueText.isEmpty {
            details.append("due \(item.dueText)")
        }
        if !details.isEmpty { line += " (\(details.joined(separator: ", ")))" }
        if let timestamp = item.timestamp { line += " @ \(TranscriptChunker.timestamp(timestamp))" }
        return line
    }

    static func metadataLine(_ document: ExportDocument) -> String {
        let date = document.createdAt.formatted(date: .long, time: .shortened)
        let duration = Duration.seconds(document.duration).formatted(.time(pattern: document.duration >= 3_600 ? .hourMinuteSecond : .minuteSecond))
        return "\(date) · \(duration)"
    }
}

extension ExportDocument {
    /// Snapshot of a recording for export; the current summary unless another is given.
    @MainActor
    static func make(from recording: Recording, summary: SummaryRecord? = nil, includeTranscript: Bool) -> ExportDocument {
        let record = summary ?? recording.currentSummary
        return ExportDocument(
            title: recording.title,
            createdAt: recording.createdAt,
            duration: recording.duration,
            speakers: recording.speakers.sorted { $0.key < $1.key }.map { ExportSpeaker(key: $0.key, displayName: $0.displayName) },
            summary: record.flatMap { try? $0.payload() },
            segments: recording.orderedSegments.map { ExportSegment(start: $0.start, speakerKey: $0.speakerKey, text: $0.text) },
            includeTranscript: includeTranscript
        )
    }
}
