import Foundation

public enum PreviewData {
    public static var sampleRecording: Recording {
        let speaker1 = Speaker(key: "S1", displayName: "Jeremy", colorIndex: 0)
        let speaker2 = Speaker(key: "S2", displayName: "Alex", colorIndex: 1)
        
        let words = [
            TimedWord(text: "Let's", start: 0.0, end: 0.3),
            TimedWord(text: "finalize", start: 0.4, end: 0.8),
            TimedWord(text: "the", start: 0.9, end: 1.0),
            TimedWord(text: "VeraFlow", start: 1.1, end: 1.6),
            TimedWord(text: "architecture.", start: 1.7, end: 2.4)
        ]
        
        let segment = TranscriptSegment(
            index: 0,
            start: 0.0,
            end: 2.4,
            text: "Let's finalize the VeraFlow architecture.",
            speakerKey: "S1",
            words: words
        )
        
        let bookmark = Bookmark(time: 1.1, note: "Key Milestone Decision")
        
        let actionItem = ActionItem(
            task: "Review M0 foundation code",
            owner: "Jeremy",
            speakerKey: "S1",
            dueText: "tomorrow",
            resolvedDueDate: Calendar.current.date(byAdding: .day, value: 1, to: Date()),
            timestamp: "00:01",
            audioTime: 1.1,
            isCompleted: false
        )
        
        let summaryRecord = SummaryRecord(
            createdAt: Date(),
            templateID: .general,
            payloadJSON: Data(),
            actionItemsState: (try? JSONEncoder().encode([actionItem])) ?? Data(),
            modelInfo: "SystemLanguageModel Preview"
        )
        
        return Recording(
            title: "VeraFlow Kickoff & Architecture Alignment",
            createdAt: Date(),
            duration: 120.0,
            audioFileName: "sample.caf",
            source: .recorded,
            stage: .ready,
            localeIdentifier: "en-US",
            templateID: .general,
            tags: ["Architecture", "Kickoff"],
            isFavorite: true,
            segments: [segment],
            speakers: [speaker1, speaker2],
            bookmarks: [bookmark],
            summaries: [summaryRecord]
        )
    }
}
