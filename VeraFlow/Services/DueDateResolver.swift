import Foundation

/// Pure Swift due date resolver combining NSDataDetector and colloquial business rules (§11.5).
public final class DueDateResolver: DueDateResolverProtocol, Sendable {
    public init() {}
    
    public func resolve(dueText: String, referenceDate: Date) -> ResolvedDueDate {
        let trimmed = dueText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ResolvedDueDate(originalText: dueText, date: nil)
        }
        
        let lower = trimmed.lowercased()
        let calendar = Calendar.current
        
        // 1. Fast-path colloquial business phrases relative to referenceDate
        if let relativeDate = resolveColloquialPhrase(lower, referenceDate: referenceDate, calendar: calendar) {
            return ResolvedDueDate(originalText: dueText, date: relativeDate, isAllDay: true)
        }
        
        // 2. NSDataDetector for natural language dates
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            let matches = detector.matches(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed))
            if let firstMatch = matches.first, let detectedDate = firstMatch.date {
                // If the detector matched a date without specific time, normalize to 17:00
                var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: detectedDate)
                
                // If year is significantly earlier than reference date (e.g. default year), align with reference date
                let refYear = calendar.component(.year, from: referenceDate)
                if let matchYear = components.year, matchYear < refYear {
                    components.year = refYear
                }
                
                let hasExplicitTime = lower.contains("am") || lower.contains("pm") || lower.contains(":") || lower.contains("o'clock")
                if !hasExplicitTime {
                    components.hour = 17
                    components.minute = 0
                    components.second = 0
                }
                
                let finalDate = calendar.date(from: components) ?? detectedDate
                return ResolvedDueDate(originalText: dueText, date: finalDate, isAllDay: !hasExplicitTime)
            }
        }
        
        return ResolvedDueDate(originalText: dueText, date: nil)
    }
    
    // MARK: - Colloquial Helpers
    
    private func resolveColloquialPhrase(_ text: String, referenceDate: Date, calendar: Calendar) -> Date? {
        var date: Date? = nil
        
        if text.contains("asap") || text.contains("immediately") || text.contains("today") {
            date = referenceDate
        } else if text.contains("tomorrow") {
            date = calendar.date(byAdding: .day, value: 1, to: referenceDate)
        } else if text.contains("next week") {
            date = calendar.date(byAdding: .day, value: 7, to: referenceDate)
        } else if text.contains("end of week") || text.contains("eow") {
            // Upcoming Friday
            date = nextWeekday(6, after: referenceDate, calendar: calendar)
        } else if text.contains("end of month") || text.contains("eom") {
            if let monthRange = calendar.range(of: .day, in: .month, for: referenceDate) {
                var comps = calendar.dateComponents([.year, .month], from: referenceDate)
                comps.day = monthRange.count
                comps.hour = 17
                comps.minute = 0
                date = calendar.date(from: comps)
            }
        } else if let daysMatch = matchInXDays(text) {
            date = calendar.date(byAdding: .day, value: daysMatch, to: referenceDate)
        } else if let weeksMatch = matchInXWeeks(text) {
            date = calendar.date(byAdding: .day, value: weeksMatch * 7, to: referenceDate)
        } else {
            // Check specific weekdays: "by Monday", "next Friday", etc.
            let weekdays: [(name: String, weekday: Int)] = [
                ("sunday", 1), ("monday", 2), ("tuesday", 3),
                ("wednesday", 4), ("thursday", 5), ("friday", 6), ("saturday", 7)
            ]
            for item in weekdays {
                if text.contains(item.name) {
                    date = nextWeekday(item.weekday, after: referenceDate, calendar: calendar)
                    break
                }
            }
        }
        
        guard let resolved = date else { return nil }
        
        // Normalize time to 17:00 (5 PM)
        var comps = calendar.dateComponents([.year, .month, .day], from: resolved)
        comps.hour = 17
        comps.minute = 0
        comps.second = 0
        return calendar.date(from: comps)
    }
    
    private func nextWeekday(_ targetWeekday: Int, after date: Date, calendar: Calendar) -> Date {
        let currentWeekday = calendar.component(.weekday, from: date)
        var daysToAdd = (targetWeekday - currentWeekday + 7) % 7
        if daysToAdd == 0 {
            daysToAdd = 7 // Next week if today is already that weekday
        }
        return calendar.date(byAdding: .day, value: daysToAdd, to: date) ?? date
    }
    
    private func matchInXDays(_ text: String) -> Int? {
        // e.g. "in 3 days", "in 2 days"
        let pattern = #"(?:in|within)\s+(\d+)\s+days?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        if let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            return Int(text[range])
        }
        return nil
    }
    
    private func matchInXWeeks(_ text: String) -> Int? {
        let pattern = #"(?:in|within)\s+(\d+)\s+weeks?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        if let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            return Int(text[range])
        }
        return nil
    }
}
