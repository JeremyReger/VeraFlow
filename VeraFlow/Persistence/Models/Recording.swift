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
    /// v1.1: the custom template chosen for this recording (plan item 13); `templateID` holds its base.
    var customTemplateID: UUID?
    /// v1.1: one line the summary should pay particular attention to (plan item 13).
    var focus: String = ""
    /// "Ask this recording" history as JSON `[StoredAskExchange]`, oldest first (v1.1). Optional
    /// so stores written before it decode unchanged.
    var askHistoryJSON: Data?
    /// How many voices this recording has, when the user has said. `nil` means they haven't, and
    /// the Settings default decides. How many people were in a room is a fact about the recording,
    /// not a preference: a number set for one meeting used to be applied to every recording after
    /// it, including voice memos (2026-09-19).
    var expectedSpeakersRaw: String?

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

    /// The count the user set for this recording, or `nil` to follow the Settings default.
    var expectedSpeakers: DiarizationPreference.ExpectedSpeakers? {
        get { expectedSpeakersRaw.flatMap(DiarizationPreference.ExpectedSpeakers.init(rawValue:)) }
        set { expectedSpeakersRaw = newValue?.rawValue }
    }

    /// The questions asked of this recording, oldest first. Unreadable history reads as none
    /// rather than throwing: it is a convenience, never the recording itself.
    func askHistory() -> [StoredAskExchange] {
        guard let askHistoryJSON, !askHistoryJSON.isEmpty else { return [] }
        return (try? JSONDecoder().decode([StoredAskExchange].self, from: askHistoryJSON)) ?? []
    }

    /// Keeps the most recent `limit` exchanges, so a long session doesn't grow the row forever.
    func storeAskHistory(_ history: [StoredAskExchange], limit: Int = Recording.askHistoryLimit) {
        let kept = Array(history.suffix(limit))
        askHistoryJSON = kept.isEmpty ? nil : try? JSONEncoder().encode(kept)
    }

    static let askHistoryLimit = 50

    /// Segments in transcript order.
    var orderedSegments: [TranscriptSegment] {
        segments.sorted { $0.index < $1.index }
    }

    /// The language the transcript is translated into (v1.1 plan item 14): the one the
    /// translated paragraphs share, `nil` when none is translated.
    var translationLanguage: String? {
        segments.first { $0.translatedText != nil }?.translationLanguage
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
