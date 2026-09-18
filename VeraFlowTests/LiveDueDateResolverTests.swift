import Foundation
import Testing
@testable import VeraFlow

/// Table-driven, against a fixed reference date (SPEC §16 M5): Thursday 2026-09-17, 10:00 Pacific.
struct LiveDueDateResolverTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }()

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 17, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private static let reference = date(2026, 9, 17, 10, 0)

    private static let table: [(phrase: String, expected: Date?)] = [
        ("tomorrow", date(2026, 9, 18)),
        ("the day after tomorrow", date(2026, 9, 19)),
        ("EOD", date(2026, 9, 17)),
        ("by end of day", date(2026, 9, 17)),
        ("today at 3pm", date(2026, 9, 17, 15)),
        ("end of week", date(2026, 9, 18)),
        ("by end of the week", date(2026, 9, 18)),
        ("next week", date(2026, 9, 21)),
        ("end of next week", date(2026, 9, 25)),
        ("next Friday", date(2026, 9, 25)),
        ("next Monday", date(2026, 9, 21)),
        ("next Thursday", date(2026, 9, 24)),
        ("by Friday", date(2026, 9, 18)),
        ("Monday", date(2026, 9, 21)),
        ("this Thursday", date(2026, 9, 17)),
        ("on Wednesday", date(2026, 9, 23)),
        ("in 3 days", date(2026, 9, 20)),
        ("within two weeks", date(2026, 10, 1)),
        ("in a month", date(2026, 10, 17)),
        ("in a couple of days", date(2026, 9, 19)),
        ("end of month", date(2026, 9, 30)),
        ("end of next month", date(2026, 10, 31)),
        ("end of year", date(2026, 12, 31)),
        ("next month", date(2026, 10, 17)),
        ("by the 30th", date(2026, 9, 30)),
        ("on the 5th", date(2026, 10, 5)),
        ("the 17th", date(2026, 9, 17)),
        ("March 3", date(2027, 3, 3)),
        ("October 2nd", date(2026, 10, 2)),
        ("Sept 30", date(2026, 9, 30)),
        ("3 March", date(2027, 3, 3)),
        ("10/2", date(2026, 10, 2)),
        ("9/30/2026", date(2026, 9, 30)),
        ("tomorrow at 9am", date(2026, 9, 18, 9)),
        ("Friday noon", date(2026, 9, 18, 12)),
        ("next Tuesday 2:30 pm", date(2026, 9, 22, 14, 30)),
        ("", nil),
        ("when the parts arrive", nil),
        ("soon", nil),
        ("later", nil),
    ]

    @Test("Phrases resolve relative to the recording date, at 5 PM unless a time was said", arguments: table.indices)
    func resolves(index: Int) {
        let (phrase, expected) = Self.table[index]
        let resolved = LiveDueDateResolver().resolve(phrase, relativeTo: Self.reference, calendar: Self.calendar)
        #expect(resolved == expected, "\"\(phrase)\" → \(String(describing: resolved)), expected \(String(describing: expected))")
    }

    @Test("A weekday said on that weekday means today, and 'next' always skips to next week")
    func weekdayEdges() {
        // Sunday 2026-09-20: "next Monday" is the very next day, since a new week starts then.
        let sunday = Self.date(2026, 9, 20, 9)
        let resolver = LiveDueDateResolver()
        #expect(resolver.resolve("next Monday", relativeTo: sunday, calendar: Self.calendar) == Self.date(2026, 9, 21))
        #expect(resolver.resolve("next week", relativeTo: sunday, calendar: Self.calendar) == Self.date(2026, 9, 21))
        #expect(resolver.resolve("Sunday", relativeTo: sunday, calendar: Self.calendar) == Self.date(2026, 9, 20))
        // Monday 2026-09-21: "next Monday" is a week out, "end of week" is that Friday.
        let monday = Self.date(2026, 9, 21, 9)
        #expect(resolver.resolve("next Monday", relativeTo: monday, calendar: Self.calendar) == Self.date(2026, 9, 28))
        #expect(resolver.resolve("end of week", relativeTo: monday, calendar: Self.calendar) == Self.date(2026, 9, 25))
        // A day number that already passed this month rolls to the next month that has it.
        let lateMonth = Self.date(2026, 9, 29, 9)
        #expect(resolver.resolve("the 31st", relativeTo: lateMonth, calendar: Self.calendar) == Self.date(2026, 10, 31))
        #expect(resolver.resolve("the 1st", relativeTo: lateMonth, calendar: Self.calendar) == Self.date(2026, 10, 1))
    }

    @Test("Explicit times are parsed in 12-hour form")
    func times() {
        #expect(LiveDueDateResolver.explicitTime(in: "9am")?.hour == 9)
        #expect(LiveDueDateResolver.explicitTime(in: "9:15 pm").map { [$0.hour, $0.minute] } == [21, 15])
        #expect(LiveDueDateResolver.explicitTime(in: "12 pm")?.hour == 12)
        #expect(LiveDueDateResolver.explicitTime(in: "12 am")?.hour == 0)
        #expect(LiveDueDateResolver.explicitTime(in: "noon")?.hour == 12)
        #expect(LiveDueDateResolver.explicitTime(in: "by friday") == nil)
    }
}
