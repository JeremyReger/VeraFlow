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

    // MARK: The one-voice notice

    @Test("A long recording heard as one voice offers the speaker count")
    func offersTheHint() {
        #expect(SpeakerCountNotice.shouldOfferHint(speakerCount: 1, duration: 131, hint: .automatic, isLabeled: true))
    }

    @Test("Nothing is offered before the labels have run, or when they found more than one voice")
    func staysQuiet() {
        // Still transcribing: one speaker means nothing yet.
        #expect(!SpeakerCountNotice.shouldOfferHint(speakerCount: 1, duration: 131, hint: .automatic, isLabeled: false))
        // Two voices found: the labels worked.
        #expect(!SpeakerCountNotice.shouldOfferHint(speakerCount: 2, duration: 131, hint: .automatic, isLabeled: true))
        // No speech at all.
        #expect(!SpeakerCountNotice.shouldOfferHint(speakerCount: 0, duration: 131, hint: .automatic, isLabeled: true))
    }

    @Test("A short memo really is one person, so it is never questioned")
    func shortRecordings() {
        #expect(!SpeakerCountNotice.shouldOfferHint(speakerCount: 1, duration: 20, hint: .automatic, isLabeled: true))
        #expect(SpeakerCountNotice.shouldOfferHint(
            speakerCount: 1,
            duration: SpeakerCountNotice.minimumDuration,
            hint: .automatic,
            isLabeled: true
        ))
    }

    @Test("Once the user has said how many people there were, the advice is not repeated")
    func hintAlreadyGiven() {
        for choice in SpeakerCountNotice.choices {
            #expect(!SpeakerCountNotice.shouldOfferHint(speakerCount: 1, duration: 131, hint: choice, isLabeled: true))
        }
        #expect(SpeakerCountNotice.choices == [.two, .three, .fourOrMore])
        #expect(!SpeakerCountNotice.choices.contains(.automatic))
    }
}
