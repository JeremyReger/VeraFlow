import Foundation
import SwiftData

/// One block of a summary the user can hide in a custom template (v1.1 plan item 13). The
/// model's output schema never changes; hidden sections are dropped at render and export time.
enum SummarySection: String, Codable, CaseIterable, Sendable, Identifiable {
    case keyPoints
    case decisions
    case actionItems
    case openQuestions
    case clientGoals
    case concerns
    case nextMeeting
    case areas
    case customerRequests
    case issuesFound
    case quoteNotes
    case chapters

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .keyPoints: "Key points"
        case .decisions: "Decisions"
        case .actionItems: "Action items"
        case .openQuestions: "Open questions"
        case .clientGoals: "Client goals"
        case .concerns: "Concerns"
        case .nextMeeting: "Next meeting"
        case .areas: "Areas and measurements"
        case .customerRequests: "Customer requests"
        case .issuesFound: "Issues found"
        case .quoteNotes: "Quote notes"
        case .chapters: "Chapters"
        }
    }

    /// The sections a base template produces, in the order the Summary tab shows them.
    static func sections(for base: TemplateID) -> [SummarySection] {
        switch base {
        case .general: [.keyPoints, .decisions, .actionItems, .openQuestions, .chapters]
        case .client: [.clientGoals, .concerns, .decisions, .actionItems, .nextMeeting, .openQuestions, .chapters]
        case .walkthrough: [.areas, .customerRequests, .issuesFound, .quoteNotes, .actionItems, .chapters]
        }
    }
}

/// A user-made template (v1.1 plan item 13): a built-in base, the sections to hide, and a
/// one-line focus for the model. Unlocked only. Recordings and summaries keep the base in
/// `templateID` and point here by id, so deleting a template leaves them on their base.
@Model
final class CustomTemplate {
    @Attribute(.unique) var id: UUID
    var name: String
    var base: TemplateID
    /// `SummarySection` raw values.
    var hiddenSectionsRaw: [String]
    var focus: String
    var createdAt: Date

    init(id: UUID = UUID(), name: String, base: TemplateID, hiddenSections: [SummarySection] = [], focus: String = "", createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.base = base
        self.hiddenSectionsRaw = hiddenSections.map(\.rawValue)
        self.focus = FocusLine.sanitize(focus)
        self.createdAt = createdAt
    }

    var hiddenSections: Set<SummarySection> {
        get { Set(hiddenSectionsRaw.compactMap(SummarySection.init(rawValue:))) }
        set { hiddenSectionsRaw = newValue.map(\.rawValue).sorted() }
    }

    /// The name that stands in for the base template's on chips and rows.
    var shortName: String { name }
}
