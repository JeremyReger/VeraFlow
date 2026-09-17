import Foundation

/// Resolves spoken due-date phrases ("next Friday", "EOD") to dates (SPEC §11.6).
/// The model never computes dates; this does, deterministically, relative to the recording date.
/// Implemented for real in M5 with `NSDataDetector` plus a small rule set.
protocol DueDateResolving: Sendable {
    /// Returns a date for `phrase`, or `nil` if it doesn't describe one.
    func resolve(_ phrase: String, relativeTo referenceDate: Date, calendar: Calendar) -> Date?
}

extension DueDateResolving {
    func resolve(_ phrase: String, relativeTo referenceDate: Date) -> Date? {
        resolve(phrase, relativeTo: referenceDate, calendar: .current)
    }
}

/// Looks phrases up in a table. Anything not in the table resolves to `nil`.
struct FakeDueDateResolver: DueDateResolving {
    /// Lowercased phrase → offset in days from the reference date.
    var offsetsByPhrase: [String: Int]

    init(offsetsByPhrase: [String: Int] = ["tomorrow": 1, "next week": 7, "eod": 0]) {
        self.offsetsByPhrase = offsetsByPhrase
    }

    func resolve(_ phrase: String, relativeTo referenceDate: Date, calendar: Calendar) -> Date? {
        let key = phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let days = offsetsByPhrase[key] else { return nil }
        return calendar.date(byAdding: .day, value: days, to: referenceDate)
    }
}
