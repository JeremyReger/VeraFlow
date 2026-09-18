import Foundation

/// Turns a spoken due-date phrase into a date, deterministically, relative to the recording date
/// (SPEC §11.6). Rules first ("EOD", "end of week", "next Friday", "in two weeks", "the 30th",
/// "March 3"), then `NSDataDetector` as a last resort with the result re-anchored to the
/// recording's year. Phrases without a time land at 5 PM. The model never computes dates.
///
/// Started from the Antigravity branch's resolver; the rules the review flagged are fixed here:
/// "next Friday" is next week's Friday, "next week" is Monday, and nothing depends on the wall clock.
struct LiveDueDateResolver: DueDateResolving {
    /// Hour used when the phrase names no time.
    var defaultHour = 17

    func resolve(_ phrase: String, relativeTo referenceDate: Date, calendar: Calendar) -> Date? {
        let text = Self.normalize(phrase)
        guard !text.isEmpty else { return nil }
        let time = Self.explicitTime(in: text)
        if let day = Self.ruleDay(for: text, referenceDate: referenceDate, calendar: calendar) {
            return Self.date(on: day, hour: time?.hour ?? defaultHour, minute: time?.minute ?? 0, calendar: calendar)
        }
        if let day = Self.detectedDay(in: phrase, referenceDate: referenceDate, calendar: calendar) {
            return Self.date(on: day, hour: time?.hour ?? defaultHour, minute: time?.minute ?? 0, calendar: calendar)
        }
        return nil
    }

    // MARK: Rules

    /// The calendar day the phrase means, or `nil` when no rule matches.
    static func ruleDay(for text: String, referenceDate: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: referenceDate)
        let weekday = calendar.component(.weekday, from: today) // 1 = Sunday … 7 = Saturday
        func days(_ n: Int) -> Date? { calendar.date(byAdding: .day, value: n, to: today) }
        func months(_ n: Int) -> Date? { calendar.date(byAdding: .month, value: n, to: today) }
        func lastDay(ofMonthContaining date: Date) -> Date? {
            guard let range = calendar.range(of: .day, in: .month, for: date) else { return nil }
            var parts = calendar.dateComponents([.year, .month], from: date)
            parts.day = range.count
            return calendar.date(from: parts)
        }
        /// Days until the coming `target` weekday; 0 when it is today.
        func daysUntil(_ target: Int) -> Int { (target - weekday + 7) % 7 }
        /// Monday of the following week (weeks run Monday–Sunday for this purpose).
        let daysToNextMonday = daysUntil(2) == 0 ? 7 : daysUntil(2)

        if containsAny(text, ["day after tomorrow"]) { return days(2) }
        if containsAny(text, ["tomorrow"]) { return days(1) }
        if containsAny(text, ["eod", "end of day", "end of the day", "today", "tonight", "asap", "right away", "immediately", "close of business", "cob"]) {
            return today
        }
        if containsAny(text, ["end of next week"]) { return days(daysToNextMonday + 4) }
        if containsAny(text, ["end of next month"]) { return months(1).flatMap(lastDay(ofMonthContaining:)) }
        if containsAny(text, ["end of month", "end of the month", "eom"]) { return lastDay(ofMonthContaining: today) }
        if containsAny(text, ["end of year", "end of the year", "eoy"]) {
            var parts = calendar.dateComponents([.year], from: today)
            parts.month = 12
            parts.day = 31
            return calendar.date(from: parts)
        }
        if containsAny(text, ["end of week", "end of the week", "eow", "this week", "end of this week"]) {
            return days(daysUntil(6))
        }
        if let (count, unit) = relativeAmount(in: text) {
            switch unit {
            case "day": return days(count)
            case "week": return days(count * 7)
            case "month": return months(count)
            default: break
            }
        }
        if let (weekdayNumber, isNext) = weekdayMention(in: text) {
            if isNext {
                return days(daysToNextMonday + (weekdayNumber - 2 + 7) % 7)
            }
            return days(daysUntil(weekdayNumber))
        }
        if containsAny(text, ["next week"]) { return days(daysToNextMonday) }
        if containsAny(text, ["next month"]) { return months(1) }
        if let (month, day, year) = monthDayMention(in: text) {
            return firstOccurrence(month: month, day: day, year: year, onOrAfter: today, calendar: calendar)
        }
        if let day = ordinalDayMention(in: text) {
            return firstOccurrence(month: nil, day: day, year: nil, onOrAfter: today, calendar: calendar)
        }
        return nil
    }

    /// "in 3 days", "within two weeks", "in a month", "a couple of days".
    static func relativeAmount(in text: String) -> (Int, String)? {
        let pattern = #"\b(?:in|within)\s+(a|an|one|two|three|four|five|six|seven|eight|nine|ten|twelve|a couple of|couple of|\d{1,3})\s+(day|week|month)s?\b"#
        guard let match = firstMatch(pattern, in: text) else { return nil }
        guard let count = number(from: match[1]) else { return nil }
        return (count, match[2])
    }

    /// The weekday named in the text and whether it was prefixed with "next".
    static func weekdayMention(in text: String) -> (Int, Bool)? {
        let names = [
            (1, "sunday|sun"), (2, "monday|mon"), (3, "tuesday|tues|tue"), (4, "wednesday|wed"),
            (5, "thursday|thurs|thu"), (6, "friday|fri"), (7, "saturday|sat"),
        ]
        for (number, alternatives) in names {
            if let match = firstMatch(#"\b(next\s+)?(?:\#(alternatives))\b"#, in: text) {
                return (number, !match[1].isEmpty)
            }
        }
        return nil
    }

    /// "March 3", "3 March", "Sept 30th", "10/2", "9/30/2026" → (month, day, year?).
    static func monthDayMention(in text: String) -> (Int, Int, Int?)? {
        if let match = firstMatch(#"\b(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b"#, in: text),
           let month = Int(match[1]), let day = Int(match[2]), (1...12).contains(month), (1...31).contains(day) {
            var year = Int(match[3])
            if let y = year, y < 100 { year = 2000 + y }
            return (month, day, year)
        }
        let months = "jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?"
        let monthNumber: (String) -> Int? = { name in
            let prefixes = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
            return prefixes.firstIndex { name.hasPrefix($0) }.map { $0 + 1 }
        }
        if let match = firstMatch(#"\b(\#(months))\.?\s+(?:the\s+)?(\d{1,2})(?:st|nd|rd|th)?(?:,?\s+(\d{4}))?\b"#, in: text),
           let month = monthNumber(match[1]), let day = Int(match[2]), (1...31).contains(day) {
            return (month, day, Int(match[3]))
        }
        if let match = firstMatch(#"\b(?:the\s+)?(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?(\#(months))\b(?:,?\s+(\d{4}))?"#, in: text),
           let month = monthNumber(match[2]), let day = Int(match[1]), (1...31).contains(day) {
            return (month, day, Int(match[3]))
        }
        return nil
    }

    /// "the 30th", "by the 5th" → day of month.
    static func ordinalDayMention(in text: String) -> Int? {
        guard let match = firstMatch(#"\b(?:the\s+)?(\d{1,2})(?:st|nd|rd|th)\b"#, in: text), let day = Int(match[1]),
              (1...31).contains(day) else { return nil }
        return day
    }

    /// "9am", "9:30 pm", "noon", "midnight".
    static func explicitTime(in text: String) -> (hour: Int, minute: Int)? {
        if containsAny(text, ["noon", "midday"]) { return (12, 0) }
        if containsAny(text, ["midnight"]) { return (0, 0) }
        guard let match = firstMatch(#"\b(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)(?![a-z])"#, in: text),
              var hour = Int(match[1]) else { return nil }
        let minute = Int(match[2]) ?? 0
        let isPM = match[3].hasPrefix("p")
        if hour == 12 { hour = 0 }
        if isPM { hour += 12 }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return (hour, minute)
    }

    // MARK: Detector fallback

    /// Anything the rules missed but `NSDataDetector` recognizes as a date. Only the month and day
    /// are trusted (the detector resolves against the wall clock); the year comes from the reference.
    static func detectedDay(in phrase: String, referenceDate: Date, calendar: Calendar) -> Date? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let range = NSRange(phrase.startIndex..., in: phrase)
        guard let match = detector.firstMatch(in: phrase, options: [], range: range), let date = match.date else { return nil }
        let parts = calendar.dateComponents([.month, .day], from: date)
        guard let month = parts.month, let day = parts.day else { return nil }
        return firstOccurrence(month: month, day: day, year: nil, onOrAfter: calendar.startOfDay(for: referenceDate), calendar: calendar)
    }

    // MARK: Helpers

    /// The first day matching `month`/`day` on or after `date`; `month == nil` means "this day number, next time it comes".
    static func firstOccurrence(month: Int?, day: Int, year: Int?, onOrAfter date: Date, calendar: Calendar) -> Date? {
        let reference = calendar.dateComponents([.year, .month, .day], from: date)
        if let year {
            return calendar.date(from: DateComponents(year: year, month: month ?? reference.month, day: day))
        }
        if let month {
            var parts = DateComponents(year: reference.year, month: month, day: day)
            if let candidate = calendar.date(from: parts), candidate >= date { return candidate }
            parts.year = (reference.year ?? 0) + 1
            return calendar.date(from: parts)
        }
        // Day of month only: this month if still ahead (or today), otherwise the next month that has it.
        var parts = DateComponents(year: reference.year, month: reference.month, day: day)
        for _ in 0..<12 {
            if let candidate = calendar.date(from: parts), candidate >= date,
               calendar.component(.day, from: candidate) == day {
                return candidate
            }
            guard let next = calendar.date(byAdding: .month, value: 1, to: calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: 1)) ?? date) else { return nil }
            parts.year = calendar.component(.year, from: next)
            parts.month = calendar.component(.month, from: next)
        }
        return nil
    }

    static func date(on day: Date, hour: Int, minute: Int, calendar: Calendar) -> Date? {
        var parts = calendar.dateComponents([.year, .month, .day], from: day)
        parts.hour = hour
        parts.minute = minute
        parts.second = 0
        return calendar.date(from: parts)
    }

    static func normalize(_ phrase: String) -> String {
        phrase.lowercased()
            .replacingOccurrences(of: "[\\u2019']", with: "", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { needle in
            firstMatch("\\b\(NSRegularExpression.escapedPattern(for: needle))\\b", in: text) != nil
        }
    }

    private static func number(from word: String) -> Int? {
        if let value = Int(word) { return value }
        let words = ["a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
                     "seven": 7, "eight": 8, "nine": 9, "ten": 10, "twelve": 12, "a couple of": 2, "couple of": 2]
        return words[word]
    }

    /// Capture groups of the first match (group 0 is the whole match); unmatched groups are "".
    private static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            guard let r = Range(match.range(at: index), in: text) else { return "" }
            return String(text[r])
        }
    }
}
