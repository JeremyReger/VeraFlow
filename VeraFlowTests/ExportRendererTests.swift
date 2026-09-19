import Foundation
import Testing
@testable import VeraFlow

@MainActor
struct ExportRendererTests {
    private var document: ExportDocument {
        ExportDocument.make(from: PreviewData.sampleRecording(), includeTranscript: true)
    }

    @Test("Markdown has the title, metadata, speakers, summary sections, checkbox action items, and the transcript")
    func markdown() {
        let markdown = ExportRenderer.markdown(for: document)
        #expect(markdown.hasPrefix("# Kitchen remodel walk-through\n"))
        #expect(markdown.contains("Speakers: Speaker 1, Speaker 2"))
        #expect(markdown.contains("## Summary\n"))
        #expect(markdown.contains("## Kitchen\n\n- Pour footer after permit"))
        #expect(markdown.contains("## Quote notes\n\n- Permit required before footer"))
        #expect(markdown.contains("- [ ] Call the county about the permit (Speaker 2, due on Monday) @ 00:04"))
        #expect(markdown.contains("## Transcript\n\n**[00:00] Speaker 1:** We need the permit"))
        #expect(!markdown.contains("Check measurements"), "no measurements in the sample, so no warning")
        #expect(markdown.hasSuffix("\n"))
    }

    @Test("Plain text carries the same content without markup; the transcript can be left out")
    func plainText() {
        let text = ExportRenderer.plainText(for: document)
        #expect(text.hasPrefix("KITCHEN REMODEL WALK-THROUGH\n"))
        #expect(text.contains("ACTION ITEMS\n☐ Call the county about the permit"))
        #expect(text.contains("TRANSCRIPT\n[00:00] Speaker 1: We need the permit"))
        #expect(!text.contains("#"))
        #expect(!text.contains("**"))

        var noTranscript = document
        noTranscript.includeTranscript = false
        #expect(!ExportRenderer.plainText(for: noTranscript).contains("TRANSCRIPT"))
        #expect(!ExportRenderer.summaryText(for: document).contains("TRANSCRIPT"))
        #expect(ExportRenderer.actionItemsText(for: document) == "☐ Call the county about the permit (Speaker 2, due on Monday) @ 00:04")
    }

    @Test("Marked moments are listed after the summary in every format, and left out when there are none")
    func markedMoments() {
        var doc = document
        #expect(doc.marks == [ExportMark(time: 3.6, label: "Permit question")], "the sample's user mark is carried")
        let markdown = ExportRenderer.markdown(for: doc)
        #expect(markdown.contains("## Marked moments\n\n- [00:04] Permit question"))
        #expect(ExportRenderer.plainText(for: doc).contains("MARKED MOMENTS\n• [00:04] Permit question"))
        doc.marks = [ExportMark(time: 65, label: ""), ExportMark(time: 10, label: "Quote")]
        let lines = ExportRenderer.contextSections(doc).first?.lines
        #expect(lines == ["- [00:10] Quote", "- [01:05] Marked moment"])
        doc.marks = []
        #expect(!ExportRenderer.markdown(for: doc).contains("Marked moments"))
    }

    @Test("Chapters are listed after the summary when the payload has two or more placed subjects")
    func chapters() {
        var doc = document
        doc.summary = .general(GeneralSummary(
            title: "t", overview: "o", keyPoints: ["a", "b"],
            topics: [KeyPointTopic(title: "Budget", points: ["a"], start: 0), KeyPointTopic(title: "Hiring", points: ["b"], start: 125)],
            decisions: [], actionItems: [], openQuestions: []
        ))
        let markdown = ExportRenderer.markdown(for: doc)
        #expect(markdown.contains("## Chapters\n\n- [00:00] Budget\n- [02:05] Hiring"))
        #expect(ExportRenderer.plainText(for: doc).contains("CHAPTERS\n• [00:00] Budget"))
    }

    @Test("Walk-through measurements get the audio-check warning and their timestamps")
    func measurements() {
        var doc = document
        doc.summary = .walkthrough(WalkthroughSummary(
            title: "t", location: "12 Elm St", overview: "o",
            areas: [WorkArea(name: "Bath", tasks: ["Tile floor"], measurements: [Measurement(item: "Floor", value: "8 ft by 6 ft", timestamp: 65)], materials: [Material(name: "Tile", quantity: "50 sq ft", notes: "")])],
            customerRequests: [], issuesFound: ["Soft subfloor"], quoteNotes: [], actionItems: []
        ))
        let markdown = ExportRenderer.markdown(for: doc)
        #expect(markdown.contains("Location: 12 Elm St"))
        #expect(markdown.contains("- Floor: 8 ft by 6 ft (@ 01:05)"))
        #expect(markdown.contains("- Material: Tile (50 sq ft)"))
        #expect(markdown.contains("> Check measurements against the audio before quoting."))
        #expect(ExportRenderer.plainText(for: doc).contains("Check measurements against the audio before quoting."))
    }

    @Test("Action item lines use the speaker's current name and the resolved date when there is one")
    func actionItemLine() {
        var doc = document
        doc.speakers = [ExportSpeaker(key: "S1", displayName: "Jeremy"), ExportSpeaker(key: "S2", displayName: "Dana")]
        let due = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 9, day: 21))!
        let item = ActionItem(task: "Send the quote", owner: "Speaker 2", ownerSpeakerKey: "S2", dueText: "Monday", dueDate: due, timestamp: 3_723)
        let line = ExportRenderer.actionItemLine(item, document: doc)
        #expect(line.hasPrefix("Send the quote (Dana, due "))
        #expect(line.hasSuffix(") @ 1:02:03"))
        #expect(ExportRenderer.actionItemLine(ActionItem(task: "Buy paint"), document: doc) == "Buy paint")
    }

    @Test("File names are the date, the title, and the extension, with unsafe characters removed")
    func fileName() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var doc = document
        doc.createdAt = calendar.date(from: DateComponents(year: 2026, month: 9, day: 17, hour: 12))!
        #expect(ExportRenderer.fileName(for: doc, fileExtension: "md", calendar: calendar) == "2026-09-17 Kitchen remodel walk-through.md")
        doc.title = "Q3: plan / review?"
        #expect(ExportRenderer.fileName(for: doc, fileExtension: "pdf", calendar: calendar) == "2026-09-17 Q3  plan   review.pdf")
        doc.title = "///"
        #expect(ExportRenderer.fileName(for: doc, fileExtension: "txt", calendar: calendar) == "2026-09-17 Recording.txt")
    }

    @Test("Reminder notes name the owner, the recording, the time, and the spoken due phrase")
    func reminderNotes() {
        let item = ActionItem(task: "Call the county", owner: "Speaker 2", ownerSpeakerKey: "S2", dueText: "on Monday", timestamp: 216)
        let request = ReminderRequest(actionItem: item, recordingTitle: "Kitchen remodel walk-through", ownerDisplayName: "Dana")
        #expect(ExportRenderer.reminderNotes(for: request) == "Owner: Dana\nFrom: Kitchen remodel walk-through @ 03:36\nDue as spoken: on Monday")
        let bare = ReminderRequest(actionItem: ActionItem(task: "x"), recordingTitle: "Standup", ownerDisplayName: "")
        #expect(ExportRenderer.reminderNotes(for: bare) == "From: Standup")
    }

    @Test("The export document snapshots the recording's current summary, speakers, and paragraphs")
    func documentBuilder() {
        let recording = PreviewData.sampleRecording()
        let doc = ExportDocument.make(from: recording, includeTranscript: false)
        #expect(doc.title == recording.title)
        #expect(doc.summary?.templateID == .walkthrough)
        #expect(doc.speakers.map(\.key) == ["S1", "S2"])
        #expect(doc.segments.count == 2)
        #expect(doc.segments.first?.speakerKey == "S1")
        #expect(!doc.includeTranscript)
        #expect(doc.speakerName(for: "S9") == "S9")
        #expect(doc.speakerName(for: nil) == "Speaker")
    }
}
