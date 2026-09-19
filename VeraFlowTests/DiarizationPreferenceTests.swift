import Foundation
import Testing
@testable import VeraFlow

struct DiarizationPreferenceTests {
    @Test("The expected-speakers setting round-trips and maps to a diarizer hint")
    func roundTrip() throws {
        let suite = "DiarizationPreferenceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(DiarizationPreference.expectedSpeakers(in: defaults) == .automatic)
        DiarizationPreference.setExpectedSpeakers(.three, in: defaults)
        #expect(DiarizationPreference.expectedSpeakers(in: defaults) == .three)

        #expect(SpeakerCountHint(.automatic) == .automatic)
        #expect(SpeakerCountHint(.two) == SpeakerCountHint(exact: 2))
        #expect(SpeakerCountHint(.fourOrMore) == SpeakerCountHint(minimum: 4))
        #expect(DiarizationPreference.ExpectedSpeakers.allCases.map(\.displayName) == ["Automatic", "2", "3", "4 or more"])
    }

    @Test("The hint says what it is, so a run that found the wrong speakers explains itself")
    func hintReadsInTheLog() {
        #expect(SpeakerCountHint.automatic.description == "automatic")
        #expect(SpeakerCountHint(.two).description == "exactly 2")
        #expect(SpeakerCountHint(.three).description == "exactly 3")
        #expect(SpeakerCountHint(.fourOrMore).description == "4 or more")
    }
}
