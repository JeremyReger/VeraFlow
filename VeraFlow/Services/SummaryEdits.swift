import Foundation

/// The user's corrections to a summary's prose (v1.1 plan item 18), stored as an overlay the
/// same way `ActionItemsState` holds action-item edits: the model's `payloadJSON` is frozen, so
/// "Summarize again" and the version history always show what the model actually wrote.
///
/// A summary's payload never changes once it is written — re-running makes a new `SummaryRecord`
/// — so a plain index into a list is a stable address for a line.

/// One editable block of a summary. Raw values are persisted; never rename a case.
///
/// Key points and work areas are not here: both render as groups, and a group's lines can't be
/// addressed by a single index. They come in a later pass.
///
/// Not to be confused with `SummarySection`, which is a custom template's list of blocks to hide
/// (plan item 13). That one names blocks to leave out; this one names blocks the user can rewrite.
enum SummaryField: String, Codable, Sendable, CaseIterable {
    // Paragraphs
    case overview
    case nextMeeting
    case location
    // Lists
    case decisions
    case openQuestions
    case clientGoals
    case concerns
    case customerRequests
    case issuesFound
    case quoteNotes

    /// Paragraph fields hold one block of prose; the rest hold a numbered list.
    var isParagraph: Bool {
        switch self {
        case .overview, .nextMeeting, .location: true
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
        case .overview, .nextMeeting, .location: "line"
        }
    }

    /// "a decision", "an issue".
    var lineNounWithArticle: String {
        let vowels: Set<Character> = ["a", "e", "i", "o", "u"]
        let isVowel = lineNoun.first.map { vowels.contains($0) } ?? false
        return "\(isVowel ? "an" : "a") \(lineNoun)"
    }
}

/// The user's version of a summary's prose. Keys are `SummaryField.rawValue`, which keeps the
/// stored JSON readable and lets an unknown field from a newer build decode and be ignored.
struct SummaryEdits: Codable, Sendable, Equatable {
    /// Field → line index → the user's text. An empty string removes that line, which is what
    /// clearing the text field in the editor means.
    var lines: [String: [Int: String]] = [:]
    /// Field → lines the user added by hand, in the order they were added.
    var added: [String: [String]] = [:]
    /// Paragraph fields → the user's text.
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

    var isEmpty: Bool { lines.isEmpty && added.isEmpty && paragraphs.isEmpty }

    /// True when `field` has been touched at all, so the tab can show "Edited by you".
    func hasEdits(in field: SummaryField) -> Bool {
        lines[field.rawValue]?.isEmpty == false
            || added[field.rawValue]?.isEmpty == false
            || paragraphs[field.rawValue] != nil
    }

    // MARK: Reading

    /// The list as the user sees it: the model's lines with replacements applied and cleared ones
    /// dropped, then the ones typed by hand.
    func resolved(_ items: [String], in field: SummaryField) -> [String] {
        let replacements = lines[field.rawValue] ?? [:]
        let kept = items.enumerated().compactMap { index, item -> String? in
            let text = (replacements[index] ?? item).trimmed
            return text.isEmpty ? nil : text
        }
        return kept + (added[field.rawValue] ?? []).map(\.trimmed).filter { !$0.isEmpty }
    }

    /// The paragraph as the user sees it.
    func resolved(_ text: String, in field: SummaryField) -> String {
        paragraphs[field.rawValue]?.trimmed ?? text
    }

    // MARK: Writing

    /// Replaces the whole list for `field` with what the editor produced. The model's lines keep
    /// their indices so an untouched line stores nothing; anything past them becomes an addition.
    mutating func replace(_ newLines: [String], model: [String], in field: SummaryField) {
        let cleaned = newLines.map(\.trimmed).filter { !$0.isEmpty }
        var replacements: [Int: String] = [:]
        for (index, original) in model.enumerated() {
            // A model line the user still has, in its own slot, and unchanged, stores nothing.
            let replacement = index < cleaned.count ? cleaned[index] : ""
            if replacement != original.trimmed { replacements[index] = replacement }
        }
        let extra = cleaned.count > model.count ? Array(cleaned[model.count...]) : []
        lines[field.rawValue] = replacements.isEmpty ? nil : replacements
        added[field.rawValue] = extra.isEmpty ? nil : extra
    }

    /// Replaces a paragraph. Setting it back to the model's own text clears the edit.
    mutating func setParagraph(_ text: String, model: String, in field: SummaryField) {
        let cleaned = text.trimmed
        paragraphs[field.rawValue] = cleaned == model.trimmed ? nil : cleaned
    }

    /// Drops every edit for one field, putting the model's own words back.
    mutating func revert(_ field: SummaryField) {
        lines[field.rawValue] = nil
        added[field.rawValue] = nil
        paragraphs[field.rawValue] = nil
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

// MARK: - Applying edits to a payload

extension SummaryPayload {
    /// The model's list for `field`, or nil when this template has no such block.
    func list(for field: SummaryField) -> [String]? {
        switch (self, field) {
        case (.general(let summary), .decisions): return summary.decisions
        case (.general(let summary), .openQuestions): return summary.openQuestions
        case (.client(let summary), .clientGoals): return summary.clientGoals
        case (.client(let summary), .concerns): return summary.concerns
        case (.client(let summary), .decisions): return summary.decisions
        case (.client(let summary), .openQuestions): return summary.openQuestions
        case (.walkthrough(let summary), .customerRequests): return summary.customerRequests
        case (.walkthrough(let summary), .issuesFound): return summary.issuesFound
        case (.walkthrough(let summary), .quoteNotes): return summary.quoteNotes
        default: return nil
        }
    }

    /// The model's paragraph for `field`, or nil when this template has no such block.
    func paragraph(for field: SummaryField) -> String? {
        switch (self, field) {
        case (_, .overview): return overview
        case (.client(let summary), .nextMeeting): return summary.nextMeeting
        case (.walkthrough(let summary), .location): return summary.location
        default: return nil
        }
    }

    /// Every field this template actually has, in the order the Summary tab draws them.
    var editableFields: [SummaryField] {
        switch self {
        case .general: [.overview, .decisions, .openQuestions]
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
            return .walkthrough(summary)
        }
    }
}

extension SummaryField: Identifiable {
    var id: String { rawValue }
}
