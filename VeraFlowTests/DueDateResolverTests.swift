import Testing
import Foundation
@testable import VeraFlow

@Suite("DueDateResolver Tests (§11.5, §16 M5)")
struct DueDateResolverTests {
    
    let calendar = Calendar.current
    let referenceDate: Date
    
    init() {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 9
        comps.day = 17 // Thursday, Sept 17, 2026
        comps.hour = 10
        comps.minute = 0
        comps.second = 0
        referenceDate = Calendar.current.date(from: comps) ?? Date()
    }
    
    @Test("Resolves 'tomorrow' relative to reference date at 17:00")
    func testTomorrow() {
        let resolver = DueDateResolver()
        let result = resolver.resolve(dueText: "by tomorrow", referenceDate: referenceDate)
        
        #expect(result.date != nil)
        if let date = result.date {
            let day = calendar.component(.day, from: date)
            let month = calendar.component(.month, from: date)
            let hour = calendar.component(.hour, from: date)
            #expect(day == 18)
            #expect(month == 9)
            #expect(hour == 17)
            #expect(result.isAllDay == true)
        }
    }
    
    @Test("Resolves 'next week' as +7 days at 17:00")
    func testNextWeek() {
        let resolver = DueDateResolver()
        let result = resolver.resolve(dueText: "finish by next week", referenceDate: referenceDate)
        
        #expect(result.date != nil)
        if let date = result.date {
            let day = calendar.component(.day, from: date)
            let month = calendar.component(.month, from: date)
            #expect(day == 24)
            #expect(month == 9)
        }
    }
    
    @Test("Resolves 'by Friday' / 'end of week' to upcoming Friday")
    func testEndOfWeekAndFriday() {
        let resolver = DueDateResolver()
        // Sept 17, 2026 is Thursday -> upcoming Friday is Sept 18, 2026
        let resultFriday = resolver.resolve(dueText: "by Friday", referenceDate: referenceDate)
        #expect(resultFriday.date != nil)
        if let date = resultFriday.date {
            let weekday = calendar.component(.weekday, from: date)
            #expect(weekday == 6) // Friday
            let day = calendar.component(.day, from: date)
            #expect(day == 18)
        }
        
        let resultEOW = resolver.resolve(dueText: "due eow", referenceDate: referenceDate)
        #expect(resultEOW.date != nil)
        if let date = resultEOW.date {
            let weekday = calendar.component(.weekday, from: date)
            #expect(weekday == 6)
        }
    }
    
    @Test("Resolves 'in 3 days'")
    func testInXDays() {
        let resolver = DueDateResolver()
        let result = resolver.resolve(dueText: "deliver in 3 days", referenceDate: referenceDate)
        
        #expect(result.date != nil)
        if let date = result.date {
            let day = calendar.component(.day, from: date)
            #expect(day == 20) // 17 + 3
        }
    }
    
    @Test("Resolves explicit date with NSDataDetector")
    func testExplicitDateString() {
        let resolver = DueDateResolver()
        let result = resolver.resolve(dueText: "October 15, 2026", referenceDate: referenceDate)
        
        #expect(result.date != nil)
        if let date = result.date {
            let month = calendar.component(.month, from: date)
            let day = calendar.component(.day, from: date)
            let year = calendar.component(.year, from: date)
            #expect(month == 10)
            #expect(day == 15)
            #expect(year == 2026)
        }
    }
    
    @Test("Returns nil date for empty string or text without date")
    func testEmptyOrInvalid() {
        let resolver = DueDateResolver()
        #expect(resolver.resolve(dueText: "", referenceDate: referenceDate).date == nil)
        #expect(resolver.resolve(dueText: "    ", referenceDate: referenceDate).date == nil)
        #expect(resolver.resolve(dueText: "as discussed in the hallway", referenceDate: referenceDate).date == nil)
    }
}
