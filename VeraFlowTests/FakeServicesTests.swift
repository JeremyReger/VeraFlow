import Foundation
import Testing
@testable import VeraFlow

/// The fakes are what previews and later tests build on, so their scripted behaviour is pinned here.
struct FakeServicesTests {
    @Test("Recorder walks through start → pause → resume → stop")
    func recorderLifecycle() async throws {
        let recorder = FakeAudioRecorderService()
        let url = URL(filePath: "/tmp/audio.caf")

        await #expect(throws: AudioRecorderError.notRecording) { try await recorder.stop() }

        try await recorder.start(to: url)
        await recorder.advance(by: 5)
        try await recorder.pause()
        await recorder.advance(by: 5) // ignored while paused
        try await recorder.resume()
        await recorder.advance(by: 2.5)
        #expect(await recorder.currentTime() == 7.5)

        let result = try await recorder.stop()
        #expect(result == RecorderResult(fileURL: url, duration: 7.5))
        #expect(await recorder.snapshot.status == .idle)
    }

    @Test("Recorder refuses to start without permission")
    func recorderPermission() async {
        let recorder = FakeAudioRecorderService(permissionGranted: false)
        #expect(await recorder.requestPermission() == false)
        await #expect(throws: AudioRecorderError.permissionDenied) {
            try await recorder.start(to: URL(filePath: "/tmp/audio.caf"))
        }
    }

    @Test("Recorder interruption auto-pauses and is delivered to listeners")
    func recorderInterruption() async throws {
        let recorder = FakeAudioRecorderService()
        try await recorder.start(to: URL(filePath: "/tmp/audio.caf"))
        let stream = await recorder.interruptions()

        await recorder.simulate(.began)
        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == .began)
        #expect(await recorder.snapshot.status == .paused)
    }

    @Test("Importer rejects unsupported file types")
    func importerRejectsUnknownTypes() async {
        let importer = FakeAudioImportService()
        await #expect(throws: AudioImportError.unsupportedType("pdf")) {
            _ = try await importer.importAudio(from: URL(filePath: "/tmp/x.pdf"), into: FileManager.default.temporaryDirectory)
        }
    }

    @Test("Fake aligner maps diarizer IDs to S1…Sn in order of first appearance")
    func alignerMapsSpeakers() {
        let aligner = FakeTranscriptAligner()
        let words = FakeTranscriptionService.sampleWords
        let segments = aligner.align(words: words, turns: FakeDiarizationService.sampleTurns)
        #expect(segments.map(\.speakerKey) == ["S1", "S2"])
        #expect(segments.flatMap(\.words) == words)
        #expect(segments.first?.text.hasPrefix("We need the permit") == true)
    }

    @Test("Fake aligner without turns yields one unlabeled paragraph")
    func alignerWithoutTurns() {
        let segments = FakeTranscriptAligner().align(words: FakeTranscriptionService.sampleWords, turns: [])
        #expect(segments.count == 1)
        #expect(segments.first?.speakerKey == nil)
        #expect(FakeTranscriptAligner().paragraphs(from: []).isEmpty)
    }

    @Test("Summarizer returns the requested template", arguments: TemplateID.allCases)
    func summarizerTemplate(template: TemplateID) async throws {
        let summarizer = FakeSummarizationService()
        let input = SummarizationInput(
            recordingTitle: "Test",
            recordedAt: .now,
            duration: 10,
            lines: [TranscriptLine(start: 0, speakerKey: "S1", speakerDisplayName: "Speaker 1", text: "Hello")],
            template: template
        )
        let payload = try await summarizer.summarize(input) { _ in }
        #expect(payload.templateID == template)
        #expect(payload.actionItems.first?.ownerSpeakerKey == "S1")
    }

    @Test("Summarizer reports unavailability instead of producing output")
    func summarizerUnavailable() async {
        let summarizer = FakeSummarizationService(availability: .deviceNotEligible)
        let input = SummarizationInput(recordingTitle: "T", recordedAt: .now, duration: 1, lines: [], template: .general)
        await #expect(throws: SummarizationError.unavailable(.deviceNotEligible)) {
            _ = try await summarizer.summarize(input) { _ in }
        }
    }

    @Test("Due date fake resolves known phrases relative to the reference date")
    func dueDateResolver() throws {
        let resolver = FakeDueDateResolver()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let reference = Date(timeIntervalSince1970: 1_789_000_000)

        let tomorrow = resolver.resolve("Tomorrow", relativeTo: reference, calendar: calendar)
        #expect(tomorrow == reference.addingTimeInterval(86_400))
        #expect(resolver.resolve("whenever", relativeTo: reference, calendar: calendar) == nil)
    }

    @Test("Export fake builds a file name of the form YYYY-MM-DD Title.ext")
    func exportFileName() async {
        let exporter = FakeExportService()
        let document = ExportDocument(
            title: "Client sync",
            createdAt: Date(timeIntervalSince1970: 1_789_000_000),
            duration: 0,
            speakers: [],
            summary: nil,
            segments: [],
            includeTranscript: false
        )
        let name = await exporter.fileName(for: document, fileExtension: "md")
        #expect(name.hasSuffix(" Client sync.md"))
        #expect(name.count == "YYYY-MM-DD Client sync.md".count)
    }

    @Test("Purchase fake gates summaries on the free-tier limit")
    func purchaseFreeTier() async throws {
        let purchases = FakePurchaseService()
        for _ in 0..<FreeTier.summaryLimit {
            #expect(await purchases.canGenerateSummary())
            await purchases.recordFreeSummaryUsed()
        }
        #expect(await purchases.canGenerateSummary() == false)

        let outcome = try await purchases.purchase()
        #expect(outcome == .purchased)
        #expect(await purchases.canGenerateSummary())
    }

    @Test("Purchase fake publishes entitlement changes")
    func purchaseEntitlementStream() async {
        let purchases = FakePurchaseService()
        let stream = await purchases.entitlementUpdates()
        await purchases.setUnlocked(true)
        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == true)
    }

    @Test("Pipeline fake records requests and forwards events")
    func pipelineFake() async {
        let pipeline = FakePipelineCoordinator()
        let id = UUID()
        let stream = await pipeline.events()
        await pipeline.enqueue(recordingID: id)
        await pipeline.emit(.stageChanged(recordingID: id, stage: .transcribing))
        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == .stageChanged(recordingID: id, stage: .transcribing))
        #expect(await pipeline.enqueued == [id])
    }

    @Test("Product ID and free limit match the spec")
    func constants() {
        #expect(ProductID.lifetimeUnlock == "veraflow.unlock.lifetime")
        #expect(FreeTier.summaryLimit == 3)
    }
}
