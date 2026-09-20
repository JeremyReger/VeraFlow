import Foundation
import os

extension SummarizationInput {
    /// The transcript as `[mm:ss] Name: text` lines plus the facts the summarizer needs (SPEC §11.3).
    /// Speaker display names are substituted here so the model sees renamed speakers. The user's
    /// marks are woven in as `★ Marked` lines in time order (v1.1 plan item 1), so the chunk that
    /// holds the moment also holds the mark; interrupted marks are not the user's and are left out.
    static func make(from recording: Recording, template: TemplateID? = nil) -> SummarizationInput {
        let names = Dictionary(recording.speakers.map { ($0.key, $0.displayName) }, uniquingKeysWith: { first, _ in first })
        let speech = recording.orderedSegments.map { segment in
            TranscriptLine(
                start: segment.start,
                speakerKey: segment.speakerKey,
                speakerDisplayName: segment.speakerKey.flatMap { names[$0] } ?? segment.speakerKey ?? "Speaker",
                text: segment.text
            )
        }
        let marks = recording.bookmarks.filter(\.isUserMark).map { TranscriptLine.mark(at: $0.time, label: $0.note) }
        let lines = merge(speech: speech, marks: marks)
        return SummarizationInput(
            recordingTitle: recording.title,
            recordedAt: recording.createdAt,
            duration: recording.duration,
            lines: lines,
            template: template ?? recording.templateID,
            focus: FocusLine.sanitize(recording.focus)
        )
    }
}

extension SummarizationInput {
    /// Speech lines in their order with each mark placed before the first line that starts at
    /// or after it (a mark at 0:00 comes first). Pure, so it's unit-tested.
    static func merge(speech: [TranscriptLine], marks: [TranscriptLine]) -> [TranscriptLine] {
        guard !marks.isEmpty else { return speech }
        var result: [TranscriptLine] = []
        var pending = marks.sorted { $0.start < $1.start }
        for line in speech {
            while let mark = pending.first, mark.start <= line.start {
                result.append(mark)
                pending.removeFirst()
            }
            result.append(line)
        }
        result.append(contentsOf: pending)
        return result
    }
}

extension ActionItemPostProcessor.Context {
    init(recording: Recording) {
        self.init(
            recordedAt: recording.createdAt,
            duration: recording.duration,
            speakers: recording.speakers.map { ($0.key, $0.displayName) },
            segments: recording.orderedSegments.map { ($0.start, $0.text) }
        )
    }
}

extension SummaryPayload {
    private static let groundingLog = Logger(subsystem: "com.jeremyreger.veraflow", category: "summaries")

    /// What grounding took out, so a device run says so rather than silently shrinking. A high
    /// count is the signal that the model is filling the schema rather than reading the transcript.
    private static func logGrounding(before: SummaryPayload, after: SummaryPayload, index: TranscriptGrounding.Index) {
        let measurements = before.measurementCount - after.measurementCount
        let areas = before.areaCount - after.areaCount
        let items = before.actionItems.count - after.actionItems.count
        if measurements > 0 || areas > 0 || items > 0 {
            groundingLog.notice("""
                grounding dropped \(areas, privacy: .public) areas, \(measurements, privacy: .public) measurements, \
                \(items, privacy: .public) action items the transcript never said
                """)
        }
        let unsupported = TranscriptGrounding.unsupportedOverviewNumbers(after, in: index)
        if !unsupported.isEmpty {
            // Kept, because a summary with no overview is worse — but it wants to be visible.
            groundingLog.notice("overview carries \(unsupported.count, privacy: .public) numbers the transcript never said")
        }
    }

    fileprivate var measurementCount: Int {
        guard case .walkthrough(let summary) = self else { return 0 }
        return summary.areas.reduce(0) { $0 + $1.measurements.count }
    }

    fileprivate var areaCount: Int {
        guard case .walkthrough(let summary) = self else { return 0 }
        return summary.areas.count
    }

    /// Runs SPEC §11.6 post-processing over every action item (and walk-through measurements'
    /// timestamps) in the payload, then validates the chapter starts (v1.1 plan item 12).
    func postProcessed(with processor: ActionItemPostProcessor, context: ActionItemPostProcessor.Context) -> SummaryPayload {
        // Grounding runs before everything else. A measurement that was never spoken must not
        // reach the chapter pass or the due-date resolver, which would give an invented figure a
        // timestamp and an invented phrase a real date on the calendar (2026-09-20).
        let index = TranscriptGrounding.index(
            segments: context.segments,
            speakers: context.speakers.map { $0.displayName }
        )
        var result = TranscriptGrounding.grounded(self, in: index)
        Self.logGrounding(before: self, after: result, index: index)

        // The model pads a thin transcript by repeating itself; drop the repeats before anything
        // downstream reads the topics, so a dropped topic never claims a chapter.
        result = SummaryDeduplicator.cleaned(result)
        let sources = result.chapterSources
        result.setChapterStarts(ChapterPostProcessor.starts(
            for: sources.map(\.title),
            given: sources.map(\.start),
            duration: context.duration,
            segments: context.segments
        ))
        let drafts = result.actionItems.map {
            ActionItemDraft(
                task: $0.task,
                owner: $0.owner,
                dueText: $0.dueText,
                timestamp: $0.timestamp.map(TranscriptChunker.timestamp) ?? ""
            )
        }
        result.actionItems = processor.process(drafts, context: context)
        if case .walkthrough(var summary) = result {
            for areaIndex in summary.areas.indices {
                for index in summary.areas[areaIndex].measurements.indices {
                    let measurement = summary.areas[areaIndex].measurements[index]
                    if let timestamp = measurement.timestamp {
                        summary.areas[areaIndex].measurements[index].timestamp = min(max(0, timestamp), context.duration)
                    } else {
                        summary.areas[areaIndex].measurements[index].timestamp =
                            ActionItemPostProcessor.nearestSegmentStart(for: measurement.item + " " + measurement.value, in: context.segments)
                    }
                }
            }
            result = .walkthrough(summary)
        }
        return result
    }
}
