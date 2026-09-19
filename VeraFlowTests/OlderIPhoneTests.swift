import Foundation
import Testing
@testable import VeraFlow

/// The iOS 18 floor (v1.1 plan item 16): which engine runs where, and what the older-iPhone
/// services report. The Parakeet run itself needs a phone on iOS 18 (see docs/PROGRESS.md).
struct OlderIPhoneTests {
    @Test("Apple's engine from iOS 26; Parakeet before that; summaries only from iOS 26")
    func policy() {
        #expect(PlatformPolicy.speechEngine(osMajorVersion: 18) == .parakeet)
        #expect(PlatformPolicy.speechEngine(osMajorVersion: 25) == .parakeet)
        #expect(PlatformPolicy.speechEngine(osMajorVersion: 26) == .appleSpeech)
        #expect(PlatformPolicy.speechEngine(osMajorVersion: 27) == .appleSpeech)
        #expect(!PlatformPolicy.summariesPossible(osMajorVersion: 18))
        #expect(PlatformPolicy.summariesPossible(osMajorVersion: 26))
    }

    @Test("On an older iPhone the capabilities say Parakeet transcribes, labels work, and nothing summarizes")
    func legacyCapabilities() async {
        let transcription = FakeTranscriptionService()
        let diarization = FakeDiarizationService()
        let service = LegacyCapabilityService(transcription: transcription, diarization: diarization, osVersion: "18.6.2")
        let capabilities = await service.refresh()
        #expect(capabilities.transcriptionEngine == .parakeet)
        #expect(capabilities.canTranscribe)
        #expect(capabilities.summarization == .deviceNotEligible)
        #expect(!capabilities.canSummarize)
        #expect(!capabilities.hasRuntimeContextSize)
        #expect(!capabilities.backgroundProcessingSupported)
        #expect(capabilities.osVersion == "18.6.2")
        #expect(OnboardingView.transcriptionMessage(capabilities).contains("Parakeet"))
        #expect(OnboardingView.summaryMessage(capabilities.summarization).contains("iOS 26"))
    }

    @Test("The unavailable summarizer and question service report the reason and refuse work")
    func unavailableServices() async {
        let summarizer = UnavailableSummarizationService()
        #expect(await summarizer.availability() == .deviceNotEligible)
        #expect(await !summarizer.supportsLanguage(Locale.Language(identifier: "en")))
        let input = SummarizationInput(recordingTitle: "t", recordedAt: .now, duration: 1, lines: [], template: .general)
        await #expect(throws: SummarizationError.unavailable(.deviceNotEligible)) {
            _ = try await summarizer.summarize(input) { _ in }
        }
        let questions = UnavailableQuestionService()
        #expect(await questions.availability() == .deviceNotEligible)
        await #expect(throws: SummarizationError.unavailable(.deviceNotEligible)) {
            _ = try await questions.answer(question: "q", excerpts: [])
        }
        let preview = UnavailableTranscriptPreview()
        #expect(await !preview.isAvailable(locale: Locale(identifier: "en-US")))
    }

    @Test("Inline background processing runs the work to completion")
    func inline() async {
        let processing = InlineBackgroundProcessing()
        let box = Box()
        await processing.run(title: "x") { progress in
            progress(1)
            await box.mark()
        }
        #expect(await box.done)
    }

    private actor Box {
        var done = false
        func mark() { done = true }
    }
}
