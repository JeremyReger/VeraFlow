import Foundation
import Testing
@testable import VeraFlow

/// The guardrail in Swift (Jeremy, 2026-09-20). A 35-second, 117-word recording came back from the
/// walkthrough template with ten rooms and twenty measurements — a house that was never walked —
/// and one of those answers was saved. The values in these tests are lifted from that log, so the
/// exact output that got through is the thing being held out.
struct TranscriptGroundingTests {

    private func index(_ transcript: String, speakers: [String] = []) -> TranscriptGrounding.Index {
        TranscriptGrounding.index(segments: [(start: 0, text: transcript)], speakers: speakers)
    }

    private func walkthrough(
        location: String = "",
        overview: String = "They walked the site.",
        areas: [WorkArea] = [],
        customerRequests: [String] = [],
        issuesFound: [String] = [],
        quoteNotes: [String] = [],
        actionItems: [ActionItem] = []
    ) -> SummaryPayload {
        .walkthrough(WalkthroughSummary(
            title: "Job Site Walkthrough",
            location: location,
            overview: overview,
            areas: areas,
            customerRequests: customerRequests,
            issuesFound: issuesFound,
            quoteNotes: quoteNotes,
            actionItems: actionItems
        ))
    }

    private func areas(of payload: SummaryPayload) -> [WorkArea] {
        guard case .walkthrough(let summary) = payload else { return [] }
        return summary.areas
    }

    // MARK: The failure that caused this

    @Test("A house nobody walked into is dropped whole")
    func invertedWalkthroughIsDropped() {
        let spoken = index("So I just wanted to record a quick note about the schedule for tomorrow.")
        let payload = walkthrough(
            location: "123 Main St.",
            areas: [
                WorkArea(name: "Kitchen",
                         tasks: ["Measure countertop space"],
                         measurements: [Measurement(item: "Kitchen wall, north", value: "12 ft 4 in", timestamp: nil)],
                         materials: []),
                WorkArea(name: "Storage room",
                         tasks: [],
                         measurements: [Measurement(item: "Storage cabinet, length", value: "8 ft 6 in", timestamp: nil)],
                         materials: []),
            ]
        )
        let result = TranscriptGrounding.grounded(payload, in: spoken)
        #expect(areas(of: result).isEmpty, "neither room was ever mentioned")
        guard case .walkthrough(let summary) = result else { Issue.record("not a walkthrough"); return }
        #expect(summary.location.isEmpty, "the address was never read out")
    }

    @Test("A room that was walked keeps its spoken measurement")
    func spokenMeasurementSurvives() {
        let spoken = index("Okay, we're in the kitchen now. The north wall is 12 ft 4 in.")
        let payload = walkthrough(areas: [
            WorkArea(name: "Kitchen",
                     tasks: [],
                     measurements: [
                        Measurement(item: "Kitchen wall, north", value: "12 ft 4 in", timestamp: nil),
                        Measurement(item: "Kitchen counter, length", value: "7 ft 6 in", timestamp: nil),
                     ],
                     materials: []),
        ])
        let result = areas(of: TranscriptGrounding.grounded(payload, in: spoken))
        #expect(result.count == 1)
        #expect(result.first?.measurements.map(\.value) == ["12 ft 4 in"],
                "7 and 6 were never spoken, so that one is invented")
    }

    // MARK: Numbers spoken as words

    @Test("A measurement read aloud in words still grounds the digits")
    func numberWordsGroundDigits() {
        let spoken = index("The north wall is twelve foot four.")
        let payload = walkthrough(areas: [
            WorkArea(name: "north wall", tasks: [],
                     measurements: [Measurement(item: "North wall", value: "12 ft 4 in", timestamp: nil)],
                     materials: []),
        ])
        #expect(areas(of: TranscriptGrounding.grounded(payload, in: spoken)).first?.measurements.count == 1)
    }

    @Test("A compound like twenty-four grounds 24 as well as 20 and 4")
    func compoundNumberWords() {
        let spoken = index("It's twenty four inches across.")
        #expect(spoken.numbersAreSpoken(in: "24 in"))
        #expect(spoken.numbersAreSpoken(in: "20 in"))
        #expect(spoken.numbersAreSpoken(in: "4 in"))
        #expect(!spoken.numbersAreSpoken(in: "25 in"))
    }

    @Test("Leading zeros and trailing decimals are the same number")
    func numberNormalization() {
        let spoken = index("Set it to 4 and 12.5.")
        #expect(spoken.numbersAreSpoken(in: "04"))
        #expect(spoken.numbersAreSpoken(in: "4.0"))
        #expect(spoken.numbersAreSpoken(in: "12.50"))
        #expect(!spoken.numbersAreSpoken(in: "12.6"))
    }

    @Test("Text with no numbers is never dropped for lacking them")
    func prosePassesWithoutNumbers() {
        let spoken = index("We talked about the paint.")
        #expect(spoken.numbersAreSpoken(in: "Customer wants the walls repainted"))
    }

    // MARK: Names

    @Test("A generic word can't be the only reason a room is kept")
    func genericWordsDoNotGround() {
        let spoken = index("Have a look at the room over there.")
        #expect(!spoken.namesSomethingSpoken("Storage room"), "'room' says nothing about which room")
        #expect(!spoken.namesSomethingSpoken("Utility room"))
    }

    @Test("A name the transcript says differently is still the same place")
    func partialNameGrounds() {
        let spoken = index("Then we went through to the master bathroom.")
        #expect(spoken.namesSomethingSpoken("Master bath"), "'master' was spoken; the model renamed it")
    }

    @Test("A material nobody mentioned is dropped, quantity or not")
    func materialsAreGrounded() {
        let spoken = index("We'll need insulation in there, about 100 square feet.")
        let payload = walkthrough(areas: [
            WorkArea(name: "insulation", tasks: [],
                     measurements: [],
                     materials: [
                        Material(name: "Insulation board", quantity: "100 sq ft", notes: ""),
                        Material(name: "Cabinet hardware", quantity: "100", notes: ""),
                        Material(name: "Insulation board", quantity: "250 sq ft", notes: ""),
                     ]),
        ])
        let result = areas(of: TranscriptGrounding.grounded(payload, in: spoken))
        #expect(result.first?.materials.map(\.name) == ["Insulation board"])
        #expect(result.first?.materials.first?.quantity == "100 sq ft", "250 was never spoken")
    }

    // MARK: Action items

    @Test("An invented due date is cleared, and the task it was attached to survives")
    func inventedDueDateIsCleared() {
        let spoken = index("Can you take a look at the drywall in the bathroom?")
        let items = [ActionItem(task: "Repair damaged drywall in bathroom", owner: "Contractor",
                                dueText: "Next week", dueDate: Date())]
        let result = TranscriptGrounding.grounded(items, spoken)
        #expect(result.count == 1, "the task itself is real")
        #expect(result.first?.dueText.isEmpty == true)
        #expect(result.first?.dueDate == nil, "an invented phrase must not reach the calendar")
        #expect(result.first?.owner.isEmpty == true, "nobody said 'Contractor'")
    }

    @Test("A due date that was spoken is kept")
    func spokenDueDateSurvives() {
        let spoken = index("Let's get that done by next Friday, Dana.")
        let items = [ActionItem(task: "Send the quote", owner: "Dana", dueText: "next Friday")]
        let result = TranscriptGrounding.grounded(items, spoken)
        #expect(result.first?.dueText == "next Friday")
        #expect(result.first?.owner == "Dana")
    }

    @Test("A speaker label counts as spoken even though no paragraph contains it")
    func speakerNamesGroundOwners() {
        let spoken = index("I'll pick that up.", speakers: ["Speaker 2"])
        let result = TranscriptGrounding.grounded([ActionItem(task: "Pick it up", owner: "Speaker 2")], spoken)
        #expect(result.first?.owner == "Speaker 2")
    }

    @Test("A task built on a number nobody said goes entirely")
    func inventedNumbersDropTheTask() {
        let spoken = index("We should add another outlet in there.")
        let items = [
            ActionItem(task: "Install 3 electrical outlets"),
            ActionItem(task: "Install another outlet"),
        ]
        let result = TranscriptGrounding.grounded(items, spoken)
        #expect(result.map(\.task) == ["Install another outlet"])
    }

    // MARK: The overview

    @Test("The overview is reported, never removed")
    func overviewIsFlaggedNotDropped() {
        let spoken = index("We walked the site and talked it over.")
        let payload = walkthrough(overview: "They reviewed 10 rooms across 3 floors.")
        let result = TranscriptGrounding.grounded(payload, in: spoken)
        #expect(result.overview == "They reviewed 10 rooms across 3 floors.",
                "a summary with no overview is worse than one with a flagged number")
        #expect(TranscriptGrounding.unsupportedOverviewNumbers(result, in: spoken) == ["10", "3"])
    }

    // MARK: General and client templates

    @Test("Key points and decisions carrying unspoken numbers go too")
    func generalListsAreGrounded() {
        let spoken = index("We agreed to ship it in two weeks.")
        let payload = SummaryPayload.general(GeneralSummary(
            title: "Planning",
            overview: "A short planning call.",
            keyPoints: ["Ship in 2 weeks", "Ship in 6 weeks"],
            topics: [],
            decisions: ["Agreed to a 2 week timeline", "Agreed to a 40% discount"],
            actionItems: [],
            openQuestions: []
        ))
        guard case .general(let result) = TranscriptGrounding.grounded(payload, in: spoken) else {
            Issue.record("not a general summary"); return
        }
        #expect(result.keyPoints == ["Ship in 2 weeks"])
        #expect(result.decisions == ["Agreed to a 2 week timeline"])
    }
}

/// How much room the model gets to answer in, which is chosen from the transcript because a bound
/// is also a budget: the full walkthrough schema offers over three hundred slots, and on a
/// 117-word recording the model filled them.
struct SummaryScaleTests {
    @Test("A short recording gets the compact schema")
    func shortTranscriptIsCompact() {
        #expect(SummaryScale.forTranscript(words: 117) == .compact)
        #expect(SummaryScale.forTranscript(words: 0) == .compact)
        #expect(SummaryScale.forTranscript(words: SummaryScale.compactWordLimit - 1) == .compact)
    }

    @Test("A real meeting gets the full schema")
    func longTranscriptIsFull() {
        #expect(SummaryScale.forTranscript(words: SummaryScale.compactWordLimit) == .full)
        #expect(SummaryScale.forTranscript(words: 5_000) == .full)
    }

    @Test("Words are counted across every kind of whitespace")
    func wordCount() {
        #expect(SummaryScale.words(in: "[00:00] Speaker 1: hello there") == 5)
        #expect(SummaryScale.words(in: "one\ntwo\tthree  four") == 4)
        #expect(SummaryScale.words(in: "   ") == 0)
    }
}
