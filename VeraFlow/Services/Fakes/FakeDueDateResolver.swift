import Foundation

public final class FakeDueDateResolver: DueDateResolverProtocol, Sendable {
    public init() {}
    
    public func resolve(dueText: String, referenceDate: Date) -> ResolvedDueDate {
        let text = dueText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.isEmpty {
            return ResolvedDueDate(originalText: dueText, date: nil)
        }
        
        let calendar = Calendar.current
        var resolvedDate: Date? = nil
        
        if text.contains("tomorrow") {
            resolvedDate = calendar.date(byAdding: .day, value: 1, to: referenceDate)
        } else if text.contains("next week") {
            resolvedDate = calendar.date(byAdding: .day, value: 7, to: referenceDate)
        } else if text.contains("friday") {
            resolvedDate = calendar.nextDate(after: referenceDate, matching: DateComponents(weekday: 6), matchingPolicy: .nextTime)
        } else {
            // Default fallback for test fixture
            resolvedDate = calendar.date(byAdding: .day, value: 3, to: referenceDate)
        }
        
        return ResolvedDueDate(originalText: dueText, date: resolvedDate)
    }
}
