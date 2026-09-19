import Foundation

/// Which exports the free tier allows (SPEC §13.2: free = plain-text copy only).
enum ExportGate {
    enum Action: Equatable, Sendable {
        case file(ExportKind)
        case copySummary
        case copyActionItems
        case email
        case reminders
        /// v1.1 plan item 13: making and using custom templates.
        case customTemplates
        /// v1.1 plan item 11: "Ask this recording".
        case ask
        /// v1.1 plan item 14: translating a recording.
        case translation
    }

    static func isAllowed(_ action: Action, unlocked: Bool) -> Bool {
        if unlocked { return true }
        switch action {
        case .copySummary, .copyActionItems: return true
        case .file, .email, .reminders, .customTemplates, .ask, .translation: return false
        }
    }

    /// Ask is unlocked only, except on the bundled sample recording so it can be tried (plan decision 1).
    static func canAsk(unlocked: Bool, isSample: Bool) -> Bool {
        isSample || isAllowed(.ask, unlocked: unlocked)
    }
}
