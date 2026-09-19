import Foundation

// Output schemas for the three v1 templates (SPEC §11.4).
// M5 adds the Foundation Models `@Generable`/`@Guide` annotations to the draft types;
// the persisted shapes below stay plain Codable so SummaryRecord doesn't depend on that framework.

/// An action item as extracted by the model, before post-processing (SPEC §11.4).
struct ActionItemDraft: Codable, Sendable, Equatable {
    /// The task, starting with a verb.
    var task: String
    /// Person responsible, exactly as named in the transcript. Empty if not stated.
    var owner: String
    /// Due date phrase exactly as spoken. Empty if none was said.
    var dueText: String
    /// "mm:ss" or "h:mm:ss" of the line where this was said.
    var timestamp: String
}

/// An action item after deterministic post-processing (SPEC §11.6).
struct ActionItem: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var task: String
    /// Free-text owner as spoken (kept even when `ownerSpeakerKey` is set).
    var owner: String
    /// Set when the owner matched a speaker label or renamed speaker.
    var ownerSpeakerKey: String?
    var dueText: String
    /// Resolved by `DueDateResolver`, never by the model. User-editable.
    var dueDate: Date?
    /// Validated and clamped to the recording duration; `nil` if it couldn't be placed.
    var timestamp: TimeInterval?

    init(
        id: UUID = UUID(),
        task: String,
        owner: String = "",
        ownerSpeakerKey: String? = nil,
        dueText: String = "",
        dueDate: Date? = nil,
        timestamp: TimeInterval? = nil
    ) {
        self.id = id
        self.task = task
        self.owner = owner
        self.ownerSpeakerKey = ownerSpeakerKey
        self.dueText = dueText
        self.dueDate = dueDate
        self.timestamp = timestamp
    }
}

/// Per-summary UI state: which action items are checked off and which reminders were created (SPEC §7).
struct ActionItemsState: Codable, Sendable, Equatable {
    var completedItemIDs: Set<UUID> = []
    /// Action item ID → EventKit reminder identifier, to avoid duplicate reminders (SPEC §12).
    var reminderIDs: [UUID: String] = [:]
}

// MARK: - Template 1: General meeting / lecture

/// Key points on one subject the meeting covered (Jeremy, 2026-09-19).
struct KeyPointTopic: Codable, Sendable, Equatable {
    var title: String
    var points: [String]
}

struct GeneralSummary: Codable, Sendable, Equatable {
    var title: String
    var overview: String
    /// Every key point in order, whatever the grouping; exports and search read this.
    var keyPoints: [String]
    /// The same points grouped by subject when the model found more than one. Older summaries
    /// have none, so the list falls back to `keyPoints`.
    var topics: [KeyPointTopic] = []
    var decisions: [String]
    var actionItems: [ActionItem]
    var openQuestions: [String]

    init(title: String, overview: String, keyPoints: [String], topics: [KeyPointTopic] = [], decisions: [String], actionItems: [ActionItem], openQuestions: [String]) {
        self.title = title
        self.overview = overview
        self.keyPoints = keyPoints
        self.topics = topics
        self.decisions = decisions
        self.actionItems = actionItems
        self.openQuestions = openQuestions
    }

    private enum CodingKeys: String, CodingKey {
        case title, overview, keyPoints, topics, decisions, actionItems, openQuestions
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        overview = try container.decode(String.self, forKey: .overview)
        keyPoints = try container.decode([String].self, forKey: .keyPoints)
        topics = try container.decodeIfPresent([KeyPointTopic].self, forKey: .topics) ?? []
        decisions = try container.decode([String].self, forKey: .decisions)
        actionItems = try container.decode([ActionItem].self, forKey: .actionItems)
        openQuestions = try container.decode([String].self, forKey: .openQuestions)
    }

    /// How the Summary tab and exports lay the key points out.
    var keyPointGroups: [KeyPointGroup] {
        KeyPointLayout.groups(topics: topics, keyPoints: keyPoints)
    }
}

/// One block of key points: a subject heading (nil for a plain list) and its points.
struct KeyPointGroup: Equatable, Sendable {
    var title: String?
    var points: [String]
}

enum KeyPointLayout {
    /// Grouped only when the model found more than one titled subject; a single subject or an
    /// older summary without topics reads as one plain list. Empty topics are dropped, and
    /// points under an untitled topic come first as a plain block.
    static func groups(topics: [KeyPointTopic], keyPoints: [String]) -> [KeyPointGroup] {
        let cleaned = topics.compactMap { topic -> KeyPointTopic? in
            let points = topic.points.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard !points.isEmpty else { return nil }
            return KeyPointTopic(title: topic.title.trimmingCharacters(in: .whitespacesAndNewlines), points: points)
        }
        let titled = cleaned.filter { !$0.title.isEmpty }
        if titled.count < 2 {
            let flat = cleaned.isEmpty ? keyPoints : cleaned.flatMap(\.points)
            return flat.isEmpty ? [] : [KeyPointGroup(title: nil, points: flat)]
        }
        var groups: [KeyPointGroup] = []
        let untitled = cleaned.filter(\.title.isEmpty).flatMap(\.points)
        if !untitled.isEmpty {
            groups.append(KeyPointGroup(title: nil, points: untitled))
        }
        groups += titled.map { KeyPointGroup(title: $0.title, points: $0.points) }
        return groups
    }
}

// MARK: - Template 2: Client / consulting meeting

struct ClientMeetingSummary: Codable, Sendable, Equatable {
    var title: String
    var overview: String
    var clientGoals: [String]
    var concerns: [String]
    var decisions: [String]
    var actionItems: [ActionItem]
    /// Next meeting or check-in if mentioned, else empty.
    var nextMeeting: String
    var openQuestions: [String]
}

/// Generated on demand from a `ClientMeetingSummary` (SPEC §11.4).
struct FollowUpEmail: Codable, Sendable, Equatable {
    var subject: String
    var body: String
}

// MARK: - Template 3: Contractor job walk-through

struct Measurement: Codable, Sendable, Equatable {
    /// e.g. "Kitchen wall, north"
    var item: String
    /// Verbatim, e.g. "12 ft 4 in". Never estimated or converted.
    var value: String
    /// Where it was said, if it could be placed.
    var timestamp: TimeInterval?
}

struct Material: Codable, Sendable, Equatable {
    var name: String
    var quantity: String
    var notes: String
}

struct WorkArea: Codable, Sendable, Equatable {
    var name: String
    var tasks: [String]
    var measurements: [Measurement]
    var materials: [Material]
}

struct WalkthroughSummary: Codable, Sendable, Equatable {
    var title: String
    /// Job address or location if spoken, else empty.
    var location: String
    var overview: String
    var areas: [WorkArea]
    var customerRequests: [String]
    var issuesFound: [String]
    var quoteNotes: [String]
    var actionItems: [ActionItem]
}

// MARK: - Persisted wrapper

/// What `SummaryRecord.payloadJSON` stores. One case per template.
enum SummaryPayload: Codable, Sendable, Equatable {
    case general(GeneralSummary)
    case client(ClientMeetingSummary)
    case walkthrough(WalkthroughSummary)

    var templateID: TemplateID {
        switch self {
        case .general: .general
        case .client: .client
        case .walkthrough: .walkthrough
        }
    }

    var title: String {
        switch self {
        case .general(let summary): summary.title
        case .client(let summary): summary.title
        case .walkthrough(let summary): summary.title
        }
    }

    var overview: String {
        switch self {
        case .general(let summary): summary.overview
        case .client(let summary): summary.overview
        case .walkthrough(let summary): summary.overview
        }
    }

    var actionItems: [ActionItem] {
        get {
            switch self {
            case .general(let summary): summary.actionItems
            case .client(let summary): summary.actionItems
            case .walkthrough(let summary): summary.actionItems
            }
        }
        set {
            switch self {
            case .general(var summary):
                summary.actionItems = newValue
                self = .general(summary)
            case .client(var summary):
                summary.actionItems = newValue
                self = .client(summary)
            case .walkthrough(var summary):
                summary.actionItems = newValue
                self = .walkthrough(summary)
            }
        }
    }

    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }
}
