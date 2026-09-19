import Foundation
import SwiftData
import Testing
@testable import VeraFlow

/// On-device translation (v1.1 plan item 14): batching, summary prose mapping, the controller
/// with a fake session, exports, and archives written before the fields existed.
@MainActor
struct TranslationTests {
    // MARK: Batching

    @Test("Blank paragraphs are skipped, ids carry the position, and results map back in order")
    func batching() {
        let texts = ["Hello", "   ", "Bye"]
        let requests = TranslationBatcher.requests(texts, prefix: "p")
        #expect(requests == [TranslationRequest(id: "p0", text: "Hello"), TranslationRequest(id: "p2", text: "Bye")])

        // Out of order and one missing: the missing one keeps its original.
        let results = [TranslationResult(id: "p2", text: "Adiós")]
        #expect(TranslationBatcher.merge(results, into: texts, prefix: "p") == ["Hello", "   ", "Adiós"])

        let many = (0..<70).map { TranslationRequest(id: String($0), text: "t\($0)") }
        let batches = TranslationBatcher.batches(many, size: 32)
        #expect(batches.map(\.count) == [32, 32, 6])
        #expect(batches.flatMap { $0 } == many)
    }

    @Test("Region variants count as the same language; display names come from the locale")
    func languages() {
        #expect(TranslationLanguages.isSame(Locale.Language(identifier: "en-US"), Locale.Language(identifier: "en-GB")))
        #expect(!TranslationLanguages.isSame(Locale.Language(identifier: "en"), Locale.Language(identifier: "es")))
        #expect(TranslationLanguages.name(for: "es", displayLocale: Locale(identifier: "en_US")) == "Spanish")
        #expect(TranslationLanguages.source(of: "en-US").languageCode?.identifier == "en")
    }

    // MARK: Summary prose

    private var walkthrough: SummaryPayload {
        .walkthrough(WalkthroughSummary(
            title: "Kitchen remodel",
            location: "12 Oak St",
            overview: "Walked the kitchen.",
            areas: [WorkArea(
                name: "Kitchen",
                tasks: ["Pour footer"],
                measurements: [VeraFlow.Measurement(item: "North wall", value: "12 ft 4 in", timestamp: 3)],
                materials: [Material(name: "Rebar", quantity: "20 pieces", notes: "Grade 60")],
                start: 0
            )],
            customerRequests: ["Island"],
            issuesFound: [],
            quoteNotes: ["Permit first"],
            actionItems: [ActionItem(task: "Call the county", owner: "Dana", dueText: "Monday", dueDate: Date(timeIntervalSince1970: 0), timestamp: 4)]
        ))
    }

    @Test("Prose is collected in a fixed order; names, values, quantities, owners, due phrases and timestamps stay put")
    func summaryStrings() {
        // Built once: the computed property makes a fresh action-item id every time it is read.
        let walkthrough = self.walkthrough
        let strings = SummaryTranslation.strings(of: walkthrough)
        #expect(strings == ["Kitchen remodel", "Walked the kitchen.", "Kitchen", "Pour footer", "North wall", "Rebar", "Grade 60", "Island", "Permit first", "Call the county"])

        let translated = SummaryTranslation.applying(strings.map { "[es] " + $0 }, to: walkthrough)
        guard case .walkthrough(let summary) = translated else { Issue.record("wrong case"); return }
        #expect(summary.title == "[es] Kitchen remodel")
        #expect(summary.location == "12 Oak St")
        #expect(summary.areas[0].measurements[0].item == "[es] North wall")
        #expect(summary.areas[0].measurements[0].value == "12 ft 4 in")
        #expect(summary.areas[0].materials[0].quantity == "20 pieces")
        #expect(summary.areas[0].materials[0].notes == "[es] Grade 60")
        #expect(summary.actionItems[0].task == "[es] Call the county")
        #expect(summary.actionItems[0].owner == "Dana")
        #expect(summary.actionItems[0].dueText == "Monday")
        #expect(summary.actionItems[0].dueDate == Date(timeIntervalSince1970: 0))
        #expect(summary.actionItems[0].timestamp == 4)
        #expect(summary.actionItems[0].id == walkthrough.actionItems[0].id, "same ids, so edits and checkboxes still apply")
        #expect(summary.areas[0].start == 0)
    }

    @Test("Applying the collected strings back gives the same payload for every template")
    func roundTrip() {
        let general = SummaryPayload.general(GeneralSummary(
            title: "Standup", overview: "Short.", keyPoints: ["a", "b"],
            topics: [KeyPointTopic(title: "Budget", points: ["a"], start: 0), KeyPointTopic(title: "Hiring", points: ["b"], start: 60)],
            decisions: ["d"], actionItems: [ActionItem(task: "t")], openQuestions: ["q"]
        ))
        let client = SummaryPayload.client(ClientMeetingSummary(
            title: "Check-in", overview: "o", clientGoals: ["g"], concerns: ["c"], decisions: ["d"],
            actionItems: [ActionItem(task: "t")], nextMeeting: "Next Tuesday", openQuestions: ["q"],
            topics: [KeyPointTopic(title: "Scope", points: ["p"], start: 0)]
        ))
        for payload in [general, client, walkthrough] {
            let strings = SummaryTranslation.strings(of: payload)
            #expect(!strings.isEmpty)
            #expect(SummaryTranslation.applying(strings, to: payload) == payload)
            // A short list leaves the tail untouched.
            #expect(SummaryTranslation.applying([], to: payload) == payload)
        }
    }

    // MARK: Controller

    @MainActor
    private struct Harness {
        let container: ModelContainer
        let recording: Recording
        var context: ModelContext { container.mainContext }
    }

    private func makeHarness() throws -> Harness {
        let container = try ModelContainerFactory.makeInMemory()
        let recording = PreviewData.sampleRecording()
        container.mainContext.insert(recording)
        try container.mainContext.save()
        return Harness(container: container, recording: recording)
    }

    /// Counts calls and can fail on a given batch.
    private actor CountingTranslator: TextTranslator {
        var calls = 0
        var failOnCall: Int?

        init(failOnCall: Int? = nil) { self.failOnCall = failOnCall }

        func translate(_ requests: [TranslationRequest]) async throws -> [TranslationResult] {
            calls += 1
            if calls == failOnCall { throw TranslationFailure.message("pack missing") }
            return requests.map { TranslationResult(id: $0.id, text: "[es] " + $0.text) }
        }
    }

    @Test("A run translates every paragraph and the current summary, stores both, and remembers the language")
    func runTranslates() async throws {
        let harness = try makeHarness()
        let controller = TranslationController()
        controller.request("es")
        #expect(controller.pendingLanguage == "es")

        let translator = CountingTranslator()
        await controller.run(recording: harness.recording, context: harness.context, translator: translator)

        #expect(controller.phase == .idle)
        #expect(controller.pendingLanguage == nil)
        let segments = harness.recording.orderedSegments
        #expect(!segments.isEmpty)
        for segment in segments {
            #expect(segment.translation(in: "es") == "[es] " + segment.text)
        }
        #expect(harness.recording.translationLanguage == "es")
        let record = try #require(harness.recording.currentSummary)
        let translated = try #require(record.translation(in: "es"))
        let original = try record.payload()
        #expect(translated.title == "[es] " + original.title)
        #expect(translated.actionItems.map(\.id) == original.actionItems.map(\.id))
        #expect(AppPreferences.translationLanguage() == "es")

        // Nothing left to translate: a second run makes no session call.
        controller.request("es")
        await controller.run(recording: harness.recording, context: harness.context, translator: translator)
        #expect(await translator.calls == 1)
    }

    @Test("A failure keeps what came back, reports a message, and the next run resumes from there")
    func runFails() async throws {
        let harness = try makeHarness()
        // Enough paragraphs for several batches.
        for index in 0..<40 {
            let segment = TranscriptSegment(index: 100 + index, start: Double(index) * 10, end: Double(index) * 10 + 5, text: "Paragraph \(index)")
            harness.recording.segments.append(segment)
        }
        try harness.context.save()
        let controller = TranslationController()
        controller.request("fr")
        let failing = CountingTranslator(failOnCall: 2)
        await controller.run(recording: harness.recording, context: harness.context, translator: failing)

        #expect(controller.phase == .failed("pack missing"))
        let translatedCount = harness.recording.segments.filter { $0.translation(in: "fr") != nil }.count
        #expect(translatedCount == TranslationBatcher.batchSize, "the first batch was stored before the failure")
        #expect(harness.recording.currentSummary?.translation(in: "fr") == nil)
        controller.dismissError()
        #expect(controller.phase == .idle)

        controller.request("fr")
        let working = CountingTranslator()
        await controller.run(recording: harness.recording, context: harness.context, translator: working)
        #expect(harness.recording.segments.allSatisfy { $0.translation(in: "fr") != nil })
        #expect(harness.recording.currentSummary?.translation(in: "fr") != nil)
    }

    @Test("Remove clears the paragraphs and every summary; Show original is a view flag only")
    func remove() async throws {
        let harness = try makeHarness()
        let controller = TranslationController()
        controller.request("de")
        await controller.run(recording: harness.recording, context: harness.context, translator: FakeTextTranslator(tag: "de"))
        #expect(harness.recording.translationLanguage == "de")
        controller.showsTranslation = false
        #expect(harness.recording.translationLanguage == "de")

        controller.remove(from: harness.recording, context: harness.context)
        #expect(harness.recording.translationLanguage == nil)
        #expect(harness.recording.segments.allSatisfy { $0.translatedText == nil && $0.translationLanguage == nil })
        #expect(harness.recording.currentSummary?.translationsJSON == nil)
    }

    @Test("Translation is unlocked-only")
    func gate() {
        #expect(!ExportGate.isAllowed(.translation, unlocked: false))
        #expect(ExportGate.isAllowed(.translation, unlocked: true))
    }

    // MARK: Exports

    @Test("Include translation adds a block with the translated summary and paragraphs after the original, in Markdown and plain text")
    func exportsCarryTranslation() async throws {
        let harness = try makeHarness()
        let controller = TranslationController()
        controller.request("es")
        await controller.run(recording: harness.recording, context: harness.context, translator: FakeTextTranslator(tag: "es"))

        let without = ExportDocument.make(from: harness.recording, includeTranscript: true)
        #expect(without.translation == nil)
        let with = ExportDocument.make(from: harness.recording, includeTranscript: true, translationLanguage: "es")
        let translation = try #require(with.translation)
        #expect(translation.segments.count == with.segments.count)
        #expect(translation.segments.allSatisfy { $0?.hasPrefix("[es] ") == true })

        let markdown = ExportRenderer.markdown(for: with)
        let originalIndex = try #require(markdown.range(of: "## Transcript")?.lowerBound)
        let translationIndex = try #require(markdown.range(of: "## Translation · ")?.lowerBound)
        #expect(originalIndex < translationIndex, "the original comes first")
        #expect(markdown.contains("### [es] Kitchen\n\n- [es] Pour footer after permit"))
        #expect(markdown.contains("- [ ] [es] Call the county about the permit (Speaker 2, due on Monday) @ 00:04"))
        #expect(markdown.contains("**[00:00] Speaker 1:** [es] We need the permit"))
        #expect(markdown.contains("> Translated to "))

        let text = ExportRenderer.plainText(for: with)
        #expect(text.contains("TRANSLATION · "))
        #expect(text.contains("☐ [es] Call the county about the permit"))
        #expect(text.contains("[00:00] Speaker 1: [es] We need the permit"))
        // Copy summary leaves the transcript out of both halves.
        #expect(!ExportRenderer.summaryText(for: with).contains("[00:00]"))

        // A language nothing was translated into adds nothing.
        #expect(ExportDocument.make(from: harness.recording, includeTranscript: true, translationLanguage: "fr").translation == nil)
    }

    // MARK: Archives

    @Test("A snapshot round-trips the translation, and one written before the fields existed decodes without them")
    func snapshots() async throws {
        let harness = try makeHarness()
        let controller = TranslationController()
        controller.request("es")
        await controller.run(recording: harness.recording, context: harness.context, translator: FakeTextTranslator(tag: "es"))

        let snapshot = RecordingSnapshot(recording: harness.recording)
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(RecordingSnapshot.self, from: data)
        #expect(decoded == snapshot)
        let restored = decoded.makeRecording()
        #expect(restored.translationLanguage == "es")
        #expect(restored.currentSummary?.translation(in: "es") != nil)

        // Strip the new keys the way an older archive would lack them.
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var segments = try #require(json["segments"] as? [[String: Any]])
        for index in segments.indices {
            segments[index]["translatedText"] = nil
            segments[index]["translationLanguage"] = nil
        }
        json["segments"] = segments
        var summaries = try #require(json["summaries"] as? [[String: Any]])
        for index in summaries.indices {
            summaries[index]["translationsJSON"] = nil
            summaries[index]["customTemplateID"] = nil
            summaries[index]["focus"] = nil
        }
        json["summaries"] = summaries
        let old = try JSONDecoder().decode(RecordingSnapshot.self, from: try JSONSerialization.data(withJSONObject: json))
        #expect(old.segments.allSatisfy { $0.translatedText == nil })
        #expect(old.summaries.allSatisfy { $0.translationsJSON == nil && $0.focus == nil })
        let older = old.makeRecording()
        #expect(older.translationLanguage == nil)
        #expect(older.currentSummary?.focus == "")
    }
}
