import Foundation
import Testing
@testable import VeraFlow

/// The user's corrections to a summary's prose (v1.1 plan item 18). The model's payload is never
/// touched, so every test here starts from a fixed payload and checks the overlay.
@MainActor
struct SummaryEditsTests {
    private func general(
        overview: String = "We agreed the launch date.",
        decisions: [String] = ["Ship on the 3rd", "Keep the beta open", "Hire a second writer"],
        openQuestions: [String] = ["Who signs off?"]
    ) -> SummaryPayload {
        .general(GeneralSummary(
            title: "Launch sync",
            overview: overview,
            keyPoints: ["One", "Two"],
            decisions: decisions,
            actionItems: [ActionItem(task: "Book the room")],
            openQuestions: openQuestions
        ))
    }

    // MARK: Lists

    @Test("An untouched section reads back exactly what the model wrote and stores nothing")
    func untouched() {
        let payload = general()
        var edits = SummaryEdits()
        edits.replace(["Ship on the 3rd", "Keep the beta open", "Hire a second writer"], model: payload.list(for: .decisions) ?? [], in: .decisions)
        #expect(edits.isEmpty)
        #expect(!edits.hasEdits(in: .decisions))
        #expect(edits.resolved(payload.list(for: .decisions) ?? [], in: .decisions) == payload.list(for: .decisions))
    }

    @Test("Rewriting one line leaves the others alone")
    func rewriteOne() {
        let payload = general()
        let model = payload.list(for: .decisions) ?? []
        var edits = SummaryEdits()
        edits.replace(["Ship on the 10th", "Keep the beta open", "Hire a second writer"], model: model, in: .decisions)
        #expect(edits.hasEdits(in: .decisions))
        #expect(edits.resolved(model, in: .decisions) == ["Ship on the 10th", "Keep the beta open", "Hire a second writer"])
        // The payload itself is untouched.
        #expect(payload.list(for: .decisions) == model)
    }

    @Test("Deleting a line drops it from the middle without shifting the rest")
    func deleteOne() {
        let payload = general()
        let model = payload.list(for: .decisions) ?? []
        var edits = SummaryEdits()
        edits.replace(["Ship on the 3rd", "Hire a second writer"], model: model, in: .decisions)
        #expect(edits.resolved(model, in: .decisions) == ["Ship on the 3rd", "Hire a second writer"])
    }

    @Test("Clearing every line empties the section but keeps the model's copy")
    func deleteAll() {
        let payload = general()
        let model = payload.list(for: .decisions) ?? []
        var edits = SummaryEdits()
        edits.replace([], model: model, in: .decisions)
        #expect(edits.resolved(model, in: .decisions).isEmpty)
        #expect(payload.list(for: .decisions)?.count == 3)
    }

    @Test("Lines typed by hand come after the model's and survive a round trip")
    func added() throws {
        let payload = general()
        let model = payload.list(for: .decisions) ?? []
        var edits = SummaryEdits()
        edits.replace(model + ["Move standup to Tuesday"], model: model, in: .decisions)
        #expect(edits.resolved(model, in: .decisions).last == "Move standup to Tuesday")
        let reopened = try JSONDecoder().decode(SummaryEdits.self, from: JSONEncoder().encode(edits))
        #expect(reopened == edits)
    }

    @Test("Blank lines are dropped and text is trimmed on save")
    func blanksDropped() {
        let payload = general()
        let model = payload.list(for: .decisions) ?? []
        var edits = SummaryEdits()
        edits.replace(["  Ship on the 3rd  ", "", "   ", "Keep the beta open", "Hire a second writer", "  "], model: model, in: .decisions)
        #expect(edits.resolved(model, in: .decisions) == ["Ship on the 3rd", "Keep the beta open", "Hire a second writer"])
    }

    @Test("Reverting a section puts the model's words back")
    func revert() {
        let payload = general()
        let model = payload.list(for: .decisions) ?? []
        var edits = SummaryEdits()
        edits.replace(["Only this one"], model: model, in: .decisions)
        #expect(edits.hasEdits(in: .decisions))
        edits.revert(.decisions)
        #expect(!edits.hasEdits(in: .decisions))
        #expect(edits.resolved(model, in: .decisions) == model)
    }

    @Test("One section's edits don't reach another")
    func sectionsAreIndependent() {
        let payload = general()
        var edits = SummaryEdits()
        edits.replace(["Only this one"], model: payload.list(for: .decisions) ?? [], in: .decisions)
        #expect(!edits.hasEdits(in: .openQuestions))
        #expect(edits.resolved(payload.list(for: .openQuestions) ?? [], in: .openQuestions) == ["Who signs off?"])
    }

    // MARK: Paragraphs

    @Test("A rewritten overview reads back; setting it to the model's own text clears the edit")
    func paragraph() {
        let payload = general()
        var edits = SummaryEdits()
        edits.setParagraph("We agreed to ship on the 10th.", model: payload.overview, in: .overview)
        #expect(edits.hasEdits(in: .overview))
        #expect(edits.resolved(payload.overview, in: .overview) == "We agreed to ship on the 10th.")
        edits.setParagraph(payload.overview, model: payload.overview, in: .overview)
        #expect(!edits.hasEdits(in: .overview))
        #expect(edits.isEmpty)
    }

    @Test("An empty paragraph field can be filled in")
    func emptyParagraph() {
        let payload = SummaryPayload.client(ClientMeetingSummary(
            title: "Kickoff",
            overview: "First call.",
            clientGoals: ["Launch by spring"],
            concerns: [],
            decisions: [],
            actionItems: [],
            nextMeeting: "",
            openQuestions: []
        ))
        #expect(payload.paragraph(for: .nextMeeting) == "")
        var edits = SummaryEdits()
        edits.setParagraph("Thursday at 10", model: "", in: .nextMeeting)
        #expect(edits.resolved(payload.paragraph(for: .nextMeeting) ?? "", in: .nextMeeting) == "Thursday at 10")
    }

    // MARK: Applying to a payload

    @Test("Applying edits rewrites the payload exports and the library card read")
    func applied() {
        let payload = general()
        var edits = SummaryEdits()
        edits.setParagraph("Shipping on the 10th.", model: payload.overview, in: .overview)
        edits.replace(["Ship on the 10th"], model: payload.list(for: .decisions) ?? [], in: .decisions)
        let resolved = payload.applying(edits)
        #expect(resolved.overview == "Shipping on the 10th.")
        #expect(resolved.list(for: .decisions) == ["Ship on the 10th"])
        // Everything else is carried through untouched.
        #expect(resolved.title == payload.title)
        #expect(resolved.actionItems == payload.actionItems)
        #expect(resolved.list(for: .openQuestions) == ["Who signs off?"])
        if case .general(let summary) = resolved {
            #expect(summary.keyPoints == ["One", "Two"])
        } else {
            Issue.record("the template changed")
        }
    }

    @Test("An empty overlay returns the payload unchanged")
    func applyingNothing() {
        let payload = general()
        #expect(payload.applying(SummaryEdits()) == payload)
    }

    @Test("Each template offers only the sections it has")
    func editableFields() {
        #expect(general().editableFields == [.overview, .keyPoints, .decisions, .openQuestions])
        #expect(general().list(for: .clientGoals) == nil)
        #expect(general().paragraph(for: .nextMeeting) == nil)
        let walkthrough = SummaryPayload.walkthrough(WalkthroughSummary(
            title: "Kitchen",
            location: "12 Mill Lane",
            overview: "Walked the kitchen.",
            areas: [],
            customerRequests: ["New splashback"],
            issuesFound: [],
            quoteNotes: [],
            actionItems: []
        ))
        #expect(walkthrough.editableFields.contains(.location))
        #expect(walkthrough.paragraph(for: .location) == "12 Mill Lane")
        #expect(walkthrough.list(for: .decisions) == nil)
    }

    @Test("Only the blocks that belong to a subject or work area need an index")
    func groupedFields() {
        let grouped = SummaryField.allCases.filter(\.isGrouped)
        #expect(Set(grouped) == [.topicPoints, .topicTitle, .areaTasks, .areaName])
        #expect(!SummaryField.keyPoints.isGrouped)
        #expect(SummaryField.topicPoints.headingField == .topicTitle)
        #expect(SummaryField.areaTasks.headingField == .areaName)
        #expect(SummaryField.decisions.headingField == nil)
        // Measurements and materials are structured pairs, not prose: no field addresses them.
        #expect(!SummaryField.allCases.contains { $0.rawValue.contains("measurement") })
        #expect(!SummaryField.allCases.contains { $0.rawValue.contains("material") })
    }

    // MARK: Subjects and work areas (tier two)

    private func grouped() -> SummaryPayload {
        .general(GeneralSummary(
            title: "Planning",
            overview: "We planned the quarter.",
            keyPoints: ["Cap is 40k", "No overtime", "Start in March"],
            topics: [
                KeyPointTopic(title: "Budget", points: ["Cap is 40k", "No overtime"]),
                KeyPointTopic(title: "Schedule", points: ["Start in March"]),
            ],
            decisions: [],
            actionItems: [],
            openQuestions: []
        ))
    }

    @Test("Each subject's points are addressed separately and don't reach the next subject")
    func topicPoints() {
        let payload = grouped()
        var edits = SummaryEdits()
        #expect(payload.list(for: .topicPoints, group: 0) == ["Cap is 40k", "No overtime"])
        #expect(payload.list(for: .topicPoints, group: 1) == ["Start in March"])
        #expect(payload.list(for: .topicPoints, group: 9) == nil)

        edits.replace(["Cap is 45k", "No overtime"], model: payload.list(for: .topicPoints, group: 0) ?? [], in: .topicPoints, group: 0)
        #expect(edits.hasEdits(in: .topicPoints, group: 0))
        #expect(!edits.hasEdits(in: .topicPoints, group: 1))
        #expect(edits.resolved(payload.list(for: .topicPoints, group: 1) ?? [], in: .topicPoints, group: 1) == ["Start in March"])
    }

    @Test("A subject's heading is edited with its points and stored beside them")
    func topicTitle() {
        let payload = grouped()
        var edits = SummaryEdits()
        #expect(payload.paragraph(for: .topicTitle, group: 1) == "Schedule")
        edits.setParagraph("Timeline", model: "Schedule", in: .topicTitle, group: 1)
        let resolved = payload.applying(edits)
        if case .general(let summary) = resolved {
            #expect(summary.topics[1].title == "Timeline")
            #expect(summary.topics[0].title == "Budget")
        } else {
            Issue.record("the template changed")
        }
    }

    @Test("Editing a subject keeps the flat key points, which exports and search read, in step")
    func flatListFollowsTheSubjects() {
        let payload = grouped()
        var edits = SummaryEdits()
        edits.replace(["Cap is 45k"], model: payload.list(for: .topicPoints, group: 0) ?? [], in: .topicPoints, group: 0)
        let resolved = payload.applying(edits)
        if case .general(let summary) = resolved {
            #expect(summary.topics[0].points == ["Cap is 45k"])
            #expect(summary.keyPoints == ["Cap is 45k", "Start in March"])
        } else {
            Issue.record("the template changed")
        }
    }

    @Test("A summary with no subjects edits its flat key points instead")
    func flatKeyPoints() {
        let payload = general()
        var edits = SummaryEdits()
        #expect(payload.list(for: .keyPoints) == ["One", "Two"])
        edits.replace(["One", "Two", "Three"], model: payload.list(for: .keyPoints) ?? [], in: .keyPoints)
        let resolved = payload.applying(edits)
        if case .general(let summary) = resolved {
            #expect(summary.keyPoints == ["One", "Two", "Three"])
            #expect(summary.topics.isEmpty)
        } else {
            Issue.record("the template changed")
        }
    }

    @Test("A work area's name and tasks are editable; its measurements and materials are not touched")
    func workAreas() {
        let payload = SummaryPayload.walkthrough(WalkthroughSummary(
            title: "Kitchen",
            location: "12 Mill Lane",
            overview: "Walked the kitchen.",
            areas: [
                WorkArea(
                    name: "Kitchen",
                    tasks: ["Strip the tiles", "Re-plaster"],
                    measurements: [Measurement(item: "North wall", value: "12 ft 4 in", timestamp: 61)],
                    materials: [Material(name: "Splashback", quantity: "3 m²", notes: "matte")]
                ),
                WorkArea(name: "Hall", tasks: ["Paint"], measurements: [], materials: []),
            ],
            customerRequests: [],
            issuesFound: [],
            quoteNotes: [],
            actionItems: []
        ))
        var edits = SummaryEdits()
        edits.setParagraph("Kitchen (rear)", model: "Kitchen", in: .areaName, group: 0)
        edits.replace(["Strip the tiles", "Re-plaster", "Seal the floor"], model: payload.list(for: .areaTasks, group: 0) ?? [], in: .areaTasks, group: 0)

        guard case .walkthrough(let resolved) = payload.applying(edits) else {
            Issue.record("the template changed")
            return
        }
        #expect(resolved.areas[0].name == "Kitchen (rear)")
        #expect(resolved.areas[0].tasks == ["Strip the tiles", "Re-plaster", "Seal the floor"])
        // Verbatim, and never the model's or the user's guess.
        #expect(resolved.areas[0].measurements == [Measurement(item: "North wall", value: "12 ft 4 in", timestamp: 61)])
        #expect(resolved.areas[0].materials.first?.quantity == "3 m²")
        #expect(resolved.areas[1].name == "Hall")
        #expect(resolved.areas[1].tasks == ["Paint"])
    }

    @Test("A block's storage key keeps the plain field name when it has no group")
    func storageKeys() throws {
        #expect(SummaryEdits.key(.decisions, group: nil) == "decisions")
        #expect(SummaryEdits.key(.topicPoints, group: 2) == "topicPoints#2")
        #expect(SummaryBlock(.topicPoints, group: 2).id == "topicPoints#2")
        #expect(SummaryBlock(.areaTasks, group: 0).heading == SummaryBlock(.areaName, group: 0))
        #expect(SummaryBlock(.decisions).heading == nil)

        // Edits written before grouped blocks existed still read back.
        let old = try JSONDecoder().decode(SummaryEdits.self, from: Data(#"{"paragraphs":{"overview":"Mine."}}"#.utf8))
        #expect(old.resolved("Theirs.", in: .overview) == "Mine.")
    }

    @Test("Subject edits survive a round trip through the record")
    func groupedStorage() throws {
        let payload = grouped()
        let record = SummaryRecord(templateID: .general, payloadJSON: try payload.encoded(), modelInfo: "test")
        var edits = SummaryEdits()
        edits.setParagraph("Timeline", model: "Schedule", in: .topicTitle, group: 1)
        edits.replace(["Start in April"], model: payload.list(for: .topicPoints, group: 1) ?? [], in: .topicPoints, group: 1)
        try record.store(edits)

        let reloaded = try record.summaryEdits()
        #expect(reloaded == edits)
        guard case .general(let resolved) = try record.resolvedPayload() else {
            Issue.record("the template changed")
            return
        }
        #expect(resolved.topics[1].title == "Timeline")
        #expect(resolved.topics[1].points == ["Start in April"])
        // The model's own output is untouched.
        guard case .general(let stored) = try record.payload() else {
            Issue.record("the template changed")
            return
        }
        #expect(stored.topics[1].title == "Schedule")
    }

    // MARK: Copy

    @Test("Every field has a heading, and list fields name one line with an article")
    func copy() {
        for field in SummaryField.allCases {
            #expect(!field.title.isEmpty)
            #expect(!field.lineNoun.isEmpty)
        }
        #expect(SummaryField.issuesFound.lineNounWithArticle == "an issue")
        #expect(SummaryField.decisions.lineNounWithArticle == "a decision")
        #expect(SummaryField.overview.isParagraph)
        #expect(!SummaryField.decisions.isParagraph)
    }

    // MARK: The editor's result

    @Test("The editor's result folds into the overlay for both kinds of section")
    func editorResult() {
        let payload = general()
        var edits = SummaryEdits()
        edits.apply(.lines(["Ship on the 10th"]), in: SummaryBlock(.decisions), model: payload)
        edits.apply(.paragraph("Shipping on the 10th."), in: SummaryBlock(.overview), model: payload)
        #expect(edits.resolved(payload.list(for: .decisions) ?? [], in: .decisions) == ["Ship on the 10th"])
        #expect(edits.resolved(payload.overview, in: .overview) == "Shipping on the 10th.")
    }

    @Test("A group result saves the heading and the lines together")
    func editorGroupResult() {
        let payload = grouped()
        var edits = SummaryEdits()
        edits.apply(
            .group(heading: "Timeline", lines: ["Start in April"]),
            in: SummaryBlock(.topicPoints, group: 1),
            model: payload
        )
        #expect(edits.resolved("Schedule", in: .topicTitle, group: 1) == "Timeline")
        #expect(edits.resolved(payload.list(for: .topicPoints, group: 1) ?? [], in: .topicPoints, group: 1) == ["Start in April"])
    }

    // MARK: Storage

    @Test("A summary record stores, reloads, and clears its edits")
    func storage() throws {
        let payload = general()
        let record = SummaryRecord(templateID: .general, payloadJSON: try payload.encoded(), modelInfo: "test")
        #expect(try record.summaryEdits().isEmpty)
        #expect(record.summaryEditsJSON == nil)

        var edits = SummaryEdits()
        edits.replace(["Ship on the 10th"], model: payload.list(for: .decisions) ?? [], in: .decisions)
        try record.store(edits)
        #expect(record.summaryEditsJSON != nil)
        #expect(try record.summaryEdits() == edits)

        // Exports and the library card see the user's wording…
        #expect(try record.resolvedPayload().list(for: .decisions) == ["Ship on the 10th"])
        // …and the model's own output is still there, untouched.
        #expect(try record.payload().list(for: .decisions)?.count == 3)

        edits.revert(.decisions)
        try record.store(edits)
        #expect(record.summaryEditsJSON == nil)
        #expect(try record.resolvedPayload().list(for: .decisions)?.count == 3)
    }

    @Test("Action-item edits and prose edits both survive into the resolved payload")
    func bothOverlays() throws {
        let item = ActionItem(task: "Book the room")
        let payload = SummaryPayload.general(GeneralSummary(
            title: "Launch sync",
            overview: "We agreed the launch date.",
            keyPoints: [],
            decisions: ["Ship on the 3rd"],
            actionItems: [item],
            openQuestions: []
        ))
        let record = SummaryRecord(templateID: .general, payloadJSON: try payload.encoded(), modelInfo: "test")

        var edits = SummaryEdits()
        edits.setParagraph("Shipping on the 10th.", model: payload.overview, in: .overview)
        try record.store(edits)

        var state = ActionItemsState()
        var renamed = item
        renamed.task = "Book the big room"
        state.save(renamed, isAdded: false)
        try record.store(state)

        let resolved = try record.resolvedPayload()
        #expect(resolved.overview == "Shipping on the 10th.")
        #expect(resolved.actionItems.first?.task == "Book the big room")
    }
}
