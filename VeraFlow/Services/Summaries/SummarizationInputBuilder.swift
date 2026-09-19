import Foundation

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
            template: template ?? recording.templateID
        )
    }
}

extension SummarizationInput {
    /// Speech lines in their order with each mark placed after the last line that starts at or
    /// before it (a mark at 0:00 comes first). Pure, so it's unit-tested.
    static func merge(speech: [TranscriptLine], marks: [TranscriptLine]) -> [TranscriptLine] {
        guard !marks.isEmpty else { return speech }
        var result: [TranscriptLine] = []
        var pending = marks.sorted { $0.start < $1.start }
        for line in speech {
            while let mark = pending.first, mark.start < line.start {
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
    /// Runs SPEC §11.6 post-processing over every action item (and walk-through measurements'
    /// timestamps) in the payload.
    func postProcessed(with processor: ActionItemPostProcessor, context: ActionItemPostProcessor.Context) -> SummaryPayload {
        var result = self
        let drafts = actionItems.map {
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
