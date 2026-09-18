import Foundation

/// Which exports the free tier allows (SPEC §13.2: free = plain-text copy only).
enum ExportGate {
    enum Action: Equatable, Sendable {
        case file(ExportKind)
        case copySummary
        case copyActionItems
        case email
        case reminders
    }

    static func isAllowed(_ action: Action, unlocked: Bool) -> Bool {
        if unlocked { return true }
        switch action {
        case .copySummary, .copyActionItems: return true
        case .file, .email, .reminders: return false
        }
    }
}
