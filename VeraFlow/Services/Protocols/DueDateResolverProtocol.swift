import Foundation

public struct ResolvedDueDate: Sendable, Hashable {
    public var originalText: String
    public var date: Date?
    public var isAllDay: Bool
    
    public init(originalText: String, date: Date?, isAllDay: Bool = true) {
        self.originalText = originalText
        self.date = date
        self.isAllDay = isAllDay
    }
}

public protocol DueDateResolverProtocol: Sendable {
    func resolve(dueText: String, referenceDate: Date) -> ResolvedDueDate
}
