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

struct GeneralSummary: Codable, Sendable, Equatable {
    var title: String
    var overview: String
    var keyPoints: [String]
    var decisions: [String]
    var actionItems: [ActionItem]
    var openQuestions: [String]
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
