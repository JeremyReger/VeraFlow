import Foundation

/// The user's corrections to a summary's prose (v1.1 plan item 18), stored as an overlay the
/// same way `ActionItemsState` holds action-item edits: the model's `payloadJSON` is frozen, so
/// "Summarize again" and the version history always show what the model actually wrote.
///
/// A summary's payload never changes once it is written — re-running makes a new `SummaryRecord`
/// — so a plain index into a list is a stable address for a line, and a plain index into
/// `topics` or `areas` is a stable address for a group.

/// One editable kind of block. Raw values are persisted; never rename a case.
///
/// The grouped kinds (`topicPoints`, `topicTitle`, `areaTasks`, `areaName`) belong to one subject
/// or work area and are addressed with its index — see `SummaryEdits.key(_:group:)`.
///
/// Not to be confused with `SummarySection`, which is a custom template's list of blocks to hide
/// (plan item 13). That one names blocks to leave out; this one names blocks the user can rewrite.
enum SummaryField: String, Codable, Sendable, CaseIterable {
    // Paragraphs
    case overview
    case nextMeeting
    case location
    // Headings: one short line above a group
    case topicTitle
    case areaName
    // Lists
    case decisions
    case openQuestions
    case clientGoals
    case concerns
    case customerRequests
    case issuesFound
    case quoteNotes
    case keyPoints
    case topicPoints
    case areaTasks

    /// Paragraph fields hold one block of prose; headings hold one short line; the rest hold a
    /// numbered list. Paragraphs and headings share the same storage.
    var isParagraph: Bool {
        switch self {
        case .overview, .nextMeeting, .location, .topicTitle, .areaName: true
        default: false
        }
    }

    /// A heading is a paragraph field that is one line, not a block of prose.
    var isHeading: Bool {
        switch self {
        case .topicTitle, .areaName: true
        default: false
        }
    }

    /// Whether this kind of block belongs to a subject or work area, and so needs its index.
    var isGrouped: Bool {
        switch self {
        case .topicPoints, .topicTitle, .areaTasks, .areaName: true
        default: false
        }
    }

    /// The heading shown above the block, and the editor's title.
    var title: String {
        switch self {
        case .overview: "Overview"
        case .nextMeeting: "Next meeting"
        case .location: "Location"
        case .decisions: "Decisions"
        case .openQuestions: "Open questions"
        case .clientGoals: "Client goals"
        case .concerns: "Concerns"
        case .customerRequests: "Customer requests"
        case .issuesFound: "Issues found"
        case .quoteNotes: "Quote notes"
        case .keyPoints, .topicPoints: "Key points"
        case .topicTitle: "Subject"
        case .areaTasks: "Work area"
        case .areaName: "Area"
        }
    }

    /// What one line is called, for "Add a decision" and the like.
    var lineNoun: String {
        switch self {
        case .decisions: "decision"
        case .openQuestions: "question"
        case .clientGoals: "goal"
        case .concerns: "concern"
        case .customerRequests: "request"
        case .issuesFound: "issue"
        case .quoteNotes: "note"
        case .keyPoints, .topicPoints: "point"
        case .areaTasks: "task"
        case .overview, .nextMeeting, .location, .topicTitle, .areaName: "line"
        }
    }

    /// "a decision", "an issue".
    var lineNounWithArticle: String {
        let vowels: Set<Character> = ["a", "e", "i", "o", "u"]
        let isVowel = lineNoun.first.map { vowels.contains($0) } ?? false
        return "\(isVowel ? "an" : "a") \(lineNoun)"
    }

    /// The heading that goes with a grouped list, when it has one.
    var headingField: SummaryField? {
        switch self {
        case .topicPoints: .topicTitle
        case .areaTasks: .areaName
        default: nil
        }
    }
}

/// One block of one summary: a field, plus the subject or work area it belongs to. The view layer
/// passes these around; the storage key is what `SummaryEdits` writes under.
struct SummaryBlock: Identifiable, Hashable, Sendable {
    var field: SummaryField
    /// Index into `topics` or `areas`; nil for a block the template has only one of.
    var group: Int?

    init(_ field: SummaryField, group: Int? = nil) {
        self.field = field
        self.group = group
    }

    var id: String { SummaryEdits.key(field, group: group) }

    /// The heading block that goes with this list, when it has one.
    var heading: SummaryBlock? {
        field.headingField.map { SummaryBlock($0, group: group) }
    }
}

/// The user's version of a summary's prose. Keys are `SummaryField.rawValue`, with `#index`
/// appended for a block inside a subject or work area. That keeps the stored JSON readable and
/// lets an unknown field from a newer build decode and be ignored.
struct SummaryEdits: Codable, Sendable, Equatable {
    /// Block key → line index → the user's text. An empty string removes that line, which is what
    /// clearing the text field in the editor means.
    var lines: [String: [Int: String]] = [:]
    /// Block key → lines the user added by hand, in the order they were added.
    var added: [String: [String]] = [:]
    /// Paragraph and heading blocks → the user's text.
    var paragraphs: [String: String] = [:]

    init(lines: [String: [Int: String]] = [:], added: [String: [String]] = [:], paragraphs: [String: String] = [:]) {
        self.lines = lines
        self.added = added
        self.paragraphs = paragraphs
    }

    private enum CodingKeys: String, CodingKey {
        case lines, added, paragraphs
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lines = try container.decodeIfPresent([String: [Int: String]].self, forKey: .lines) ?? [:]
        added = try container.decodeIfPresent([String: [String]].self, forKey: .added) ?? [:]
        paragraphs = try container.decodeIfPresent([String: String].self, forKey: .paragraphs) ?? [:]
    }

    /// Where one block's edits are stored. A block with no group keeps the plain field name, so
    /// edits written before grouped blocks existed still read back.
    static func key(_ field: SummaryField, group: Int?) -> String {
        guard let group else { return field.rawValue }
        return "\(field.rawValue)#\(group)"
    }

    var isEmpty: Bool { lines.isEmpty && added.isEmpty && paragraphs.isEmpty }

    /// True when the block has been touched at all, so the tab can show "Edited by you".
    func hasEdits(in field: SummaryField, group: Int? = nil) -> Bool {
        let key = Self.key(field, group: group)
        return lines[key]?.isEmpty == false
            || added[key]?.isEmpty == false
            || paragraphs[key] != nil
    }

    // MARK: Reading

    /// The list as the user sees it: the model's lines with replacements applied and cleared ones
    /// dropped, then the ones typed by hand.
    func resolved(_ items: [String], in field: SummaryField, group: Int? = nil) -> [String] {
        let key = Self.key(field, group: group)
        let replacements = lines[key] ?? [:]
        let kept = items.enumerated().compactMap { index, item -> String? in
            let text = (replacements[index] ?? item).trimmed
            return text.isEmpty ? nil : text
        }
        return kept + (added[key] ?? []).map(\.trimmed).filter { !$0.isEmpty }
    }

    /// The paragraph or heading as the user sees it.
    func resolved(_ text: String, in field: SummaryField, group: Int? = nil) -> String {
        paragraphs[Self.key(field, group: group)]?.trimmed ?? text
    }

    // MARK: Writing

    /// Replaces the whole list for a block with what the editor produced. The model's lines keep
    /// their indices so an untouched line stores nothing; anything past them becomes an addition.
    mutating func replace(_ newLines: [String], model: [String], in field: SummaryField, group: Int? = nil) {
        let key = Self.key(field, group: group)
        let cleaned = newLines.map(\.trimmed).filter { !$0.isEmpty }
        var replacements: [Int: String] = [:]
        for (index, original) in model.enumerated() {
            // A model line the user still has, in its own slot, and unchanged, stores nothing.
            let replacement = index < cleaned.count ? cleaned[index] : ""
            if replacement != original.trimmed { replacements[index] = replacement }
        }
        let extra = cleaned.count > model.count ? Array(cleaned[model.count...]) : []
        lines[key] = replacements.isEmpty ? nil : replacements
        added[key] = extra.isEmpty ? nil : extra
    }

    /// Replaces a paragraph or heading. Setting it back to the model's own text clears the edit.
    mutating func setParagraph(_ text: String, model: String, in field: SummaryField, group: Int? = nil) {
        let cleaned = text.trimmed
        paragraphs[Self.key(field, group: group)] = cleaned == model.trimmed ? nil : cleaned
    }

    /// Drops every edit for one block, putting the model's own words back.
    mutating func revert(_ field: SummaryField, group: Int? = nil) {
        let key = Self.key(field, group: group)
        lines[key] = nil
        added[key] = nil
        paragraphs[key] = nil
    }

    // MARK: Groups

    /// Every subject with the user's corrections written in, indices kept so the addresses hold.
    func resolvedTopics(_ topics: [KeyPointTopic]) -> [KeyPointTopic] {
        topics.enumerated().map { index, topic in
            var copy = topic
            copy.title = resolved(topic.title, in: .topicTitle, group: index)
            copy.points = resolved(topic.points, in: .topicPoints, group: index)
            return copy
        }
    }

    /// Every work area with the user's corrections written in. Measurements and materials are
    /// structured pairs, not prose, and are left exactly as the model gave them.
    func resolvedAreas(_ areas: [WorkArea]) -> [WorkArea] {
        areas.enumerated().map { index, area in
            var copy = area
            copy.name = resolved(area.name, in: .areaName, group: index)
            copy.tasks = resolved(area.tasks, in: .areaTasks, group: index)
            return copy
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

// MARK: - Applying edits to a payload

extension SummaryPayload {
    /// The model's list for a block, or nil when this template has no such block.
    func list(for field: SummaryField, group: Int? = nil) -> [String]? {
        switch (self, field) {
        case (.general(let summary), .decisions): return summary.decisions
        case (.general(let summary), .openQuestions): return summary.openQuestions
        case (.general(let summary), .keyPoints): return summary.keyPoints
        case (.general(let summary), .topicPoints):
            guard let group, summary.topics.indices.contains(group) else { return nil }
            return summary.topics[group].points
        case (.client(let summary), .clientGoals): return summary.clientGoals
        case (.client(let summary), .concerns): return summary.concerns
        case (.client(let summary), .decisions): return summary.decisions
        case (.client(let summary), .openQuestions): return summary.openQuestions
        case (.walkthrough(let summary), .customerRequests): return summary.customerRequests
        case (.walkthrough(let summary), .issuesFound): return summary.issuesFound
        case (.walkthrough(let summary), .quoteNotes): return summary.quoteNotes
        case (.walkthrough(let summary), .areaTasks):
            guard let group, summary.areas.indices.contains(group) else { return nil }
            return summary.areas[group].tasks
        default: return nil
        }
    }

    /// The model's paragraph or heading for a block, or nil when this template has no such block.
    func paragraph(for field: SummaryField, group: Int? = nil) -> String? {
        switch (self, field) {
        case (_, .overview): return overview
        case (.client(let summary), .nextMeeting): return summary.nextMeeting
        case (.walkthrough(let summary), .location): return summary.location
        case (.general(let summary), .topicTitle):
            guard let group, summary.topics.indices.contains(group) else { return nil }
            return summary.topics[group].title
        case (.walkthrough(let summary), .areaName):
            guard let group, summary.areas.indices.contains(group) else { return nil }
            return summary.areas[group].name
        default: return nil
        }
    }

    /// Every block this template has only one of, in the order the Summary tab draws them. The
    /// grouped blocks aren't here: they are reached from the subject or area they belong to.
    var editableFields: [SummaryField] {
        switch self {
        case .general: [.overview, .keyPoints, .decisions, .openQuestions]
        case .client: [.overview, .clientGoals, .concerns, .decisions, .nextMeeting, .openQuestions]
        case .walkthrough: [.overview, .location, .customerRequests, .issuesFound, .quoteNotes]
        }
    }

    /// The payload the user sees: the model's output with the prose edits written in. Exports,
    /// the library card and the follow-up email all read this, so a correction travels with the
    /// summary wherever it goes.
    func applying(_ edits: SummaryEdits) -> SummaryPayload {
        guard !edits.isEmpty else { return self }
        switch self {
        case .general(var summary):
            summary.overview = edits.resolved(summary.overview, in: .overview)
            summary.decisions = edits.resolved(summary.decisions, in: .decisions)
            summary.openQuestions = edits.resolved(summary.openQuestions, in: .openQuestions)
            let topics = edits.resolvedTopics(summary.topics)
            if topics == summary.topics {
                summary.keyPoints = edits.resolved(summary.keyPoints, in: .keyPoints)
            } else {
                // The summarizer writes `keyPoints` as the topics flattened, and exports and
                // search read it; keep the two in step when a subject is edited.
                summary.topics = topics
                summary.keyPoints = topics.flatMap(\.points)
            }
            return .general(summary)
        case .client(var summary):
            summary.overview = edits.resolved(summary.overview, in: .overview)
            summary.clientGoals = edits.resolved(summary.clientGoals, in: .clientGoals)
            summary.concerns = edits.resolved(summary.concerns, in: .concerns)
            summary.decisions = edits.resolved(summary.decisions, in: .decisions)
            summary.nextMeeting = edits.resolved(summary.nextMeeting, in: .nextMeeting)
            summary.openQuestions = edits.resolved(summary.openQuestions, in: .openQuestions)
            return .client(summary)
        case .walkthrough(var summary):
            summary.overview = edits.resolved(summary.overview, in: .overview)
            summary.location = edits.resolved(summary.location, in: .location)
            summary.customerRequests = edits.resolved(summary.customerRequests, in: .customerRequests)
            summary.issuesFound = edits.resolved(summary.issuesFound, in: .issuesFound)
            summary.quoteNotes = edits.resolved(summary.quoteNotes, in: .quoteNotes)
            summary.areas = edits.resolvedAreas(summary.areas)
            return .walkthrough(summary)
        }
    }
}

extension SummaryField: Identifiable {
    var id: String { rawValue }
}
