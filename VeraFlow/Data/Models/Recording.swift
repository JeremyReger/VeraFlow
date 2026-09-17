import Foundation
import SwiftData

/// Top-level model representing an audio recording session (§7)
@Model
public final class Recording {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var createdAt: Date
    public var duration: TimeInterval
    public var audioFileName: String
    public var sourceRawValue: String
    public var stageRawValue: String
    public var failureMessage: String?
    public var localeIdentifier: String
    public var templateIDRawValue: String
    public var tags: [String]
    public var isFavorite: Bool
    
    @Relationship(deleteRule: .cascade) public var segments: [TranscriptSegment]
    @Relationship(deleteRule: .cascade) public var speakers: [Speaker]
    @Relationship(deleteRule: .cascade) public var bookmarks: [Bookmark]
    @Relationship(deleteRule: .cascade) public var summaries: [SummaryRecord]
    
    public var source: RecordingSource {
        get { RecordingSource(rawValue: sourceRawValue) ?? .recorded }
        set { sourceRawValue = newValue.rawValue }
    }
    
    public var stage: PipelineStage {
        get { PipelineStage(rawValue: stageRawValue) ?? .recorded }
        set { stageRawValue = newValue.rawValue }
    }
    
    public var templateID: TemplateID {
        get { TemplateID(rawValue: templateIDRawValue) ?? .general }
        set { templateIDRawValue = newValue.rawValue }
    }
    
    public init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        duration: TimeInterval = 0,
        audioFileName: String = "",
        source: RecordingSource = .recorded,
        stage: PipelineStage = .recorded,
        failureMessage: String? = nil,
        localeIdentifier: String = "en-US",
        templateID: TemplateID = .general,
        tags: [String] = [],
        isFavorite: Bool = false,
        segments: [TranscriptSegment] = [],
        speakers: [Speaker] = [],
        bookmarks: [Bookmark] = [],
        summaries: [SummaryRecord] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.duration = duration
        self.audioFileName = audioFileName
        self.sourceRawValue = source.rawValue
        self.stageRawValue = stage.rawValue
        self.failureMessage = failureMessage
        self.localeIdentifier = localeIdentifier
        self.templateIDRawValue = templateID.rawValue
        self.tags = tags
        self.isFavorite = isFavorite
        self.segments = segments
        self.speakers = speakers
        self.bookmarks = bookmarks
        self.summaries = summaries
    }
}
