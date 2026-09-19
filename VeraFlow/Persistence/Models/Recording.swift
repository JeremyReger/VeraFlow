import Foundation
import SwiftData

/// A recorded or imported audio file plus everything derived from it (SPEC §7).
@Model
final class Recording {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var duration: TimeInterval
    /// File name relative to this recording's folder (see `RecordingStorage`).
    var audioFileName: String
    var source: RecordingSource
    var stage: PipelineStage
    var failureMessage: String?
    /// BCP-47 locale identifier, e.g. "en-US".
    var localeIdentifier: String
    var templateID: TemplateID
    var tags: [String]
    var isFavorite: Bool
    /// Which speech engine produced the transcript (SPEC §9.1); `nil` until transcribed.
    var transcriptionEngine: TranscriptionEngine?
    /// The stage that was running when `stage` became `.failed`, so Retry knows where to resume.
    var failedStage: PipelineStage?
    /// v1.1: set when the recording is in Recently Deleted; swept after 30 days (plan item 10).
    var deletedAt: Date?
    /// v1.1: false when the audio file is gone (an archive without audio, plan item 5); the
    /// transcript, labels and summary stay usable, playback is hidden.
    var audioAvailable: Bool = true

    @Relationship(deleteRule: .cascade, inverse: \TranscriptSegment.recording)
    var segments: [TranscriptSegment]

    @Relationship(deleteRule: .cascade, inverse: \Speaker.recording)
    var speakers: [Speaker]

    @Relationship(deleteRule: .cascade, inverse: \Bookmark.recording)
    var bookmarks: [Bookmark]

    /// Summary history; the newest is the current one.
    @Relationship(deleteRule: .cascade, inverse: \SummaryRecord.recording)
    var summaries: [SummaryRecord]

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = .now,
        duration: TimeInterval = 0,
        audioFileName: String = "audio.aac",
        source: RecordingSource = .recorded,
        stage: PipelineStage = .recording,
        failureMessage: String? = nil,
        localeIdentifier: String = Locale.current.identifier(.bcp47),
        templateID: TemplateID = .general,
        tags: [String] = [],
        isFavorite: Bool = false
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.duration = duration
        self.audioFileName = audioFileName
        self.source = source
        self.stage = stage
        self.failureMessage = failureMessage
        self.localeIdentifier = localeIdentifier
        self.templateID = templateID
        self.tags = tags
        self.isFavorite = isFavorite
        self.segments = []
        self.speakers = []
        self.bookmarks = []
        self.summaries = []
    }

    /// In Recently Deleted (plan item 10).
    var isTrashed: Bool { deletedAt != nil }

    /// Segments in transcript order.
    var orderedSegments: [TranscriptSegment] {
        segments.sorted { $0.index < $1.index }
    }

    /// The most recent summary, if any.
    var currentSummary: SummaryRecord? {
        summaries.max { $0.createdAt < $1.createdAt }
    }

    /// Default title for a new recording, e.g. "Meeting · Sep 17, 2:30 PM" (SPEC §4.2).
    /// True while the title is still the automatic "Meeting · date" one, i.e. nobody named it.
    var hasDefaultTitle: Bool {
        title.hasPrefix("Meeting · ")
    }

    static func suggestedTitle(for date: Date = .now, locale: Locale = .current) -> String {
        let formatted = date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale)
        )
        return "Meeting · \(formatted)"
    }
}
