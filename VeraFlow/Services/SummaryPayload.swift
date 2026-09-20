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

/// The user's version of one action item (v1.1 plan item 2): a full snapshot of the editable
/// fields, so the model's output in the payload is never touched.
struct ActionItemOverride: Codable, Sendable, Equatable {
    var task: String
    var owner: String
    var ownerSpeakerKey: String?
    var dueText: String
    var dueDate: Date?

    init(task: String, owner: String = "", ownerSpeakerKey: String? = nil, dueText: String = "", dueDate: Date? = nil) {
        self.task = task
        self.owner = owner
        self.ownerSpeakerKey = ownerSpeakerKey
        self.dueText = dueText
        self.dueDate = dueDate
    }

    init(_ item: ActionItem) {
        self.init(task: item.task, owner: item.owner, ownerSpeakerKey: item.ownerSpeakerKey, dueText: item.dueText, dueDate: item.dueDate)
    }

    func applied(to item: ActionItem) -> ActionItem {
        var result = item
        result.task = task
        result.owner = owner
        result.ownerSpeakerKey = ownerSpeakerKey
        result.dueText = dueText
        result.dueDate = dueDate
        return result
    }
}

/// Per-summary UI state: which action items are checked off, which reminders were created
/// (SPEC §7), and the user's edits (v1.1 plan item 2). Older records lack the edit keys.
struct ActionItemsState: Codable, Sendable, Equatable {
    var completedItemIDs: Set<UUID> = []
    /// Action item ID → EventKit reminder identifier, to avoid duplicate reminders (SPEC §12).
    var reminderIDs: [UUID: String] = [:]
    /// Edits to the model's items, by item ID.
    var overrides: [UUID: ActionItemOverride] = [:]
    /// Items the user added by hand; they have no timestamp.
    var added: [ActionItem] = []
    /// Model items the user deleted.
    var removedItemIDs: Set<UUID> = []

    init(completedItemIDs: Set<UUID> = [], reminderIDs: [UUID: String] = [:], overrides: [UUID: ActionItemOverride] = [:], added: [ActionItem] = [], removedItemIDs: Set<UUID> = []) {
        self.completedItemIDs = completedItemIDs
        self.reminderIDs = reminderIDs
        self.overrides = overrides
        self.added = added
        self.removedItemIDs = removedItemIDs
    }

    private enum CodingKeys: String, CodingKey {
        case completedItemIDs, reminderIDs, overrides, added, removedItemIDs
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        completedItemIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .completedItemIDs) ?? []
        reminderIDs = try container.decodeIfPresent([UUID: String].self, forKey: .reminderIDs) ?? [:]
        overrides = try container.decodeIfPresent([UUID: ActionItemOverride].self, forKey: .overrides) ?? [:]
        added = try container.decodeIfPresent([ActionItem].self, forKey: .added) ?? []
        removedItemIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .removedItemIDs) ?? []
    }

    var hasEdits: Bool { !overrides.isEmpty || !added.isEmpty || !removedItemIDs.isEmpty }

    /// Records an edit: a model item gets an override, an added item is replaced in place.
    mutating func save(_ item: ActionItem, isAdded: Bool) {
        if isAdded || added.contains(where: { $0.id == item.id }) {
            if let index = added.firstIndex(where: { $0.id == item.id }) {
                added[index] = item
            } else {
                added.append(item)
            }
        } else {
            overrides[item.id] = ActionItemOverride(item)
        }
    }

    /// Deletes an item: an added one goes away, a model one is hidden.
    mutating func remove(_ id: UUID) {
        if let index = added.firstIndex(where: { $0.id == id }) {
            added.remove(at: index)
        } else {
            removedItemIDs.insert(id)
            overrides[id] = nil
        }
        completedItemIDs.remove(id)
    }

    func isAdded(_ id: UUID) -> Bool {
        added.contains { $0.id == id }
    }
}

// MARK: - Template 1: General meeting / lecture

/// Key points on one subject the meeting covered (Jeremy, 2026-09-19).
struct KeyPointTopic: Codable, Sendable, Equatable {
    var title: String
    var points: [String]
    /// Where the subject starts, validated by `ChapterPostProcessor` (v1.1 plan item 12);
    /// absent on older summaries.
    var start: TimeInterval?

    init(title: String, points: [String], start: TimeInterval? = nil) {
        self.title = title
        self.points = points
        self.start = start
    }
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

/// Where a rendered block of key points came from, so an edit can be written back to the right
/// place in the stored summary (v1.1 plan item 18, tier two).
enum KeyPointSource: Equatable, Sendable {
    /// The flat `keyPoints` array: this summary has no subjects.
    case flat
    /// `topics[index]`, and only that one, so its points and its heading are editable.
    case topic(Int)
    /// Several subjects drawn as one block. There is no single place to write an edit, so the
    /// block is read-only; it takes two or more untitled subjects to reach this.
    case merged
}

/// One block of key points: a subject heading (nil for a plain list), its points, and where they
/// came from.
struct KeyPointGroup: Equatable, Sendable {
    var title: String?
    var points: [String]
    var source: KeyPointSource = .flat
}

enum KeyPointLayout {
    /// Grouped only when the model found more than one titled subject; a single subject or an
    /// older summary without topics reads as one plain list. Empty topics are dropped, and
    /// points under an untitled topic come first as a plain block. Each group carries the index
    /// of the topic it came from — the index in the *stored* array, not in the cleaned one.
    static func groups(topics: [KeyPointTopic], keyPoints: [String]) -> [KeyPointGroup] {
        let cleaned = topics.enumerated().compactMap { index, topic -> (index: Int, topic: KeyPointTopic)? in
            let points = topic.points.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard !points.isEmpty else { return nil }
            return (index, KeyPointTopic(title: topic.title.trimmingCharacters(in: .whitespacesAndNewlines), points: points))
        }
        let titled = cleaned.filter { !$0.topic.title.isEmpty }
        if titled.count < 2 {
            let flat = cleaned.isEmpty ? keyPoints : cleaned.flatMap(\.topic.points)
            guard !flat.isEmpty else { return [] }
            return [KeyPointGroup(title: nil, points: flat, source: source(of: cleaned))]
        }
        var groups: [KeyPointGroup] = []
        let untitled = cleaned.filter(\.topic.title.isEmpty)
        if !untitled.isEmpty {
            groups.append(KeyPointGroup(
                title: nil,
                points: untitled.flatMap(\.topic.points),
                source: source(of: untitled)
            ))
        }
        groups += titled.map { KeyPointGroup(title: $0.topic.title, points: $0.topic.points, source: .topic($0.index)) }
        return groups
    }

    /// One subject is editable in place; none means the flat list; several merged are not.
    private static func source(of topics: [(index: Int, topic: KeyPointTopic)]) -> KeyPointSource {
        switch topics.count {
        case 0: .flat
        case 1: .topic(topics[0].index)
        default: .merged
        }
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
    /// Subjects in the order discussed, for chapters (v1.1 plan item 12). Older summaries have none.
    var topics: [KeyPointTopic] = []

    init(title: String, overview: String, clientGoals: [String], concerns: [String], decisions: [String], actionItems: [ActionItem], nextMeeting: String, openQuestions: [String], topics: [KeyPointTopic] = []) {
        self.title = title
        self.overview = overview
        self.clientGoals = clientGoals
        self.concerns = concerns
        self.decisions = decisions
        self.actionItems = actionItems
        self.nextMeeting = nextMeeting
        self.openQuestions = openQuestions
        self.topics = topics
    }

    private enum CodingKeys: String, CodingKey {
        case title, overview, clientGoals, concerns, decisions, actionItems, nextMeeting, openQuestions, topics
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        overview = try container.decode(String.self, forKey: .overview)
        clientGoals = try container.decode([String].self, forKey: .clientGoals)
        concerns = try container.decode([String].self, forKey: .concerns)
        decisions = try container.decode([String].self, forKey: .decisions)
        actionItems = try container.decode([ActionItem].self, forKey: .actionItems)
        nextMeeting = try container.decode(String.self, forKey: .nextMeeting)
        openQuestions = try container.decode([String].self, forKey: .openQuestions)
        topics = try container.decodeIfPresent([KeyPointTopic].self, forKey: .topics) ?? []
    }
}

/// Generated on demand from a `ClientMeetingSummary` (SPEC §11.4).
struct FollowUpEmail: Codable, Sendable, Equatable {
    var subject: String
    var body: String
}

// MARK: - Template 3: Contractor job walk-through

struct Measurement: Codable, Sendable, Equatable {
    /// What was measured, named as the transcript names it.
    var item: String
    /// Word for word as spoken. Never estimated, rounded or converted, and dropped outright by
    /// `TranscriptGrounding` when a number in it was never said.
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
    /// Where the walk reached this area, validated by `ChapterPostProcessor` (v1.1 plan item 12).
    var start: TimeInterval?

    init(name: String, tasks: [String], measurements: [Measurement], materials: [Material], start: TimeInterval? = nil) {
        self.name = name
        self.tasks = tasks
        self.measurements = measurements
        self.materials = materials
        self.start = start
    }
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

    /// The action items as the user sees them: the model's items minus the deleted ones, with
    /// edits applied, then the ones added by hand (v1.1 plan item 2).
    func resolvedActionItems(applying state: ActionItemsState) -> [ActionItem] {
        let kept = actionItems.compactMap { item -> ActionItem? in
            guard !state.removedItemIDs.contains(item.id) else { return nil }
            return state.overrides[item.id]?.applied(to: item) ?? item
        }
        return kept + state.added
    }

    // MARK: Chapters (v1.1 plan item 12)

    /// (title, start) for every topic or area, validated or not.
    var chapterSources: [(title: String, start: TimeInterval?)] {
        switch self {
        case .general(let summary): summary.topics.map { ($0.title, $0.start) }
        case .client(let summary): summary.topics.map { ($0.title, $0.start) }
        case .walkthrough(let summary): summary.areas.map { ($0.name, $0.start) }
        }
    }

    /// Navigable chapters; empty unless at least two subjects were placed.
    var chapters: [Chapter] {
        ChapterPostProcessor.chapters(titles: chapterSources.map(\.title), starts: chapterSources.map(\.start))
    }

    /// Writes validated starts back into the topics or areas.
    mutating func setChapterStarts(_ starts: [TimeInterval?]) {
        switch self {
        case .general(var summary):
            for index in summary.topics.indices where index < starts.count { summary.topics[index].start = starts[index] }
            self = .general(summary)
        case .client(var summary):
            for index in summary.topics.indices where index < starts.count { summary.topics[index].start = starts[index] }
            self = .client(summary)
        case .walkthrough(var summary):
            for index in summary.areas.indices where index < starts.count { summary.areas[index].start = starts[index] }
            self = .walkthrough(summary)
        }
    }
}
