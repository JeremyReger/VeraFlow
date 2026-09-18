import Foundation
import Testing
@testable import VeraFlow

struct SpokenFormatTests {
    private let english = Locale(identifier: "en_US")

    @Test("Durations are spoken in words, not digit groups")
    func durations() {
        #expect(SpokenFormat.duration(225, locale: english) == "3 minutes, 45 seconds")
        #expect(SpokenFormat.duration(3_661, locale: english) == "1 hour, 1 minute, 1 second")
        #expect(SpokenFormat.duration(0, locale: english) == "0 seconds")
        #expect(SpokenFormat.duration(-5, locale: english) == "0 seconds")
    }

    @Test("Raw speaker keys read as Speaker n; anything else is left alone")
    func speakerKeys() {
        #expect(SpokenFormat.speakerName(forKey: "S1") == "Speaker 1")
        #expect(SpokenFormat.speakerName(forKey: "S12") == "Speaker 12")
        #expect(SpokenFormat.speakerName(forKey: "Don") == "Don")
        #expect(SpokenFormat.speakerName(forKey: "Sx") == "Sx")
    }
}
