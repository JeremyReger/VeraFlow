import Foundation

/// A recording and everything derived from it as plain data, for the library archive
/// (v1.1 plan item 5). Every stored field is here so a round trip loses nothing.
struct RecordingSnapshot: Codable, Sendable, Equatable {
    struct Segment: Codable, Sendable, Equatable {
        var index: Int
        var start: TimeInterval
        var end: TimeInterval
        var text: String
        var originalText: String
        var speakerKey: String?
        var words: [TimedWord]
        /// v1.1 plan item 14; absent in archives written before translation existed.
        var translatedText: String?
        var translationLanguage: String?
    }

    struct SpeakerEntry: Codable, Sendable, Equatable {
        var key: String
        var displayName: String
        var colorIndex: Int
    }

    struct Mark: Codable, Sendable, Equatable {
        var time: TimeInterval
        var note: String?
        var kind: BookmarkKind
    }

    struct Summary: Codable, Sendable, Equatable {
        var id: UUID
        var createdAt: Date
        var templateID: TemplateID
        var payloadJSON: Data
        var actionItemsState: Data
        var modelInfo: String
        var customTemplateID: UUID?
        var focus: String?
        var translationsJSON: Data?
        /// v1.1: the user's prose edits; absent in archives written before they existed.
        var summaryEditsJSON: Data?
    }

    var id: UUID
    var title: String
    var createdAt: Date
    var duration: TimeInterval
    var audioFileName: String
    var source: RecordingSource
    var stage: PipelineStage
    var failureMessage: String?
    var failedStage: PipelineStage?
    var localeIdentifier: String
    var templateID: TemplateID
    var tags: [String]
    var isFavorite: Bool
    var transcriptionEngine: TranscriptionEngine?
    var audioAvailable: Bool
    /// v1.1: the Ask history; absent in archives written before it existed.
    var askHistoryJSON: Data?
    var segments: [Segment]
    var speakers: [SpeakerEntry]
    var marks: [Mark]
    var summaries: [Summary]

    @MainActor
    init(recording: Recording) {
        id = recording.id
        title = recording.title
        createdAt = recording.createdAt
        duration = recording.duration
        audioFileName = recording.audioFileName
        source = recording.source
        stage = recording.stage
        failureMessage = recording.failureMessage
        failedStage = recording.failedStage
        localeIdentifier = recording.localeIdentifier
        templateID = recording.templateID
        tags = recording.tags
        isFavorite = recording.isFavorite
        transcriptionEngine = recording.transcriptionEngine
        audioAvailable = recording.audioAvailable
        askHistoryJSON = recording.askHistoryJSON
        segments = recording.orderedSegments.map {
            Segment(index: $0.index, start: $0.start, end: $0.end, text: $0.text, originalText: $0.originalText, speakerKey: $0.speakerKey, words: $0.words, translatedText: $0.translatedText, translationLanguage: $0.translationLanguage)
        }
        speakers = recording.speakers.sorted { $0.key < $1.key }.map {
            SpeakerEntry(key: $0.key, displayName: $0.displayName, colorIndex: $0.colorIndex)
        }
        marks = recording.bookmarks.sorted { $0.time < $1.time }.map {
            Mark(time: $0.time, note: $0.note, kind: $0.kind)
        }
        summaries = recording.summaries.sorted { $0.createdAt < $1.createdAt }.map {
            Summary(id: $0.id, createdAt: $0.createdAt, templateID: $0.templateID, payloadJSON: $0.payloadJSON, actionItemsState: $0.actionItemsState, modelInfo: $0.modelInfo, customTemplateID: $0.customTemplateID, focus: $0.focus, translationsJSON: $0.translationsJSON, summaryEditsJSON: $0.summaryEditsJSON)
        }
    }

    /// A fresh model object with all children. `source` and `extraTags` let the bundled sample
    /// be marked on import (plan item 7).
    @MainActor
    func makeRecording(source overrideSource: RecordingSource? = nil, extraTags: [String] = []) -> Recording {
        let recording = Recording(
            id: id,
            title: title,
            createdAt: createdAt,
            duration: duration,
            audioFileName: audioFileName,
            source: overrideSource ?? source,
            stage: stage,
            failureMessage: failureMessage,
            localeIdentifier: localeIdentifier,
            templateID: templateID,
            tags: LibraryActions.normalized(tags + extraTags),
            isFavorite: isFavorite
        )
        recording.failedStage = failedStage
        recording.transcriptionEngine = transcriptionEngine
        recording.audioAvailable = audioAvailable
        recording.askHistoryJSON = askHistoryJSON
        recording.segments = segments.map {
            let segment = TranscriptSegment(index: $0.index, start: $0.start, end: $0.end, text: $0.text, originalText: $0.originalText, speakerKey: $0.speakerKey, words: $0.words)
            segment.translatedText = $0.translatedText
            segment.translationLanguage = $0.translationLanguage
            return segment
        }
        recording.speakers = speakers.map { Speaker(key: $0.key, displayName: $0.displayName, colorIndex: $0.colorIndex) }
        recording.bookmarks = marks.map { Bookmark(time: $0.time, note: $0.note, kind: $0.kind) }
        recording.summaries = summaries.map {
            let record = SummaryRecord(id: $0.id, createdAt: $0.createdAt, templateID: $0.templateID, payloadJSON: $0.payloadJSON, actionItemsState: $0.actionItemsState, modelInfo: $0.modelInfo)
            record.customTemplateID = $0.customTemplateID
            record.focus = $0.focus ?? ""
            record.translationsJSON = $0.translationsJSON
            record.summaryEditsJSON = $0.summaryEditsJSON
            return record
        }
        return recording
    }
}
