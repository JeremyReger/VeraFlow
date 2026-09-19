import Foundation
import Testing
@testable import VeraFlow

struct ProcessingStepsTests {
    private func steps(
        _ stage: PipelineStage,
        failedStage: PipelineStage? = nil,
        message: String? = nil,
        fraction: Double = 0,
        preparing: Bool = false,
        canSummarize: Bool = true
    ) -> [ProcessingStep] {
        ProcessingSteps.steps(
            stage: stage, failedStage: failedStage, failureMessage: message,
            fraction: fraction, isPreparingAssets: preparing, canSummarize: canSummarize
        )
    }

    @Test("Transcribing: audio saved, transcription active with a percent, the rest queued")
    func transcribing() {
        let result = steps(.transcribing, fraction: 0.62)
        #expect(result.map(\.state) == [.done, .active, .queued, .queued])
        #expect(result[1].detail == "62 percent")
        #expect(ProcessingSteps.overallFraction(result, activeFraction: 0.62) == (1 + 0.62) / 4)
    }

    @Test("A one-time model download is named instead of a percent")
    func preparing() {
        #expect(steps(.transcribing, preparing: true)[1].detail == "Downloading the speech model, one time")
        #expect(steps(.diarizing, preparing: true)[2].detail == "Downloading the speaker-label models, one time")
    }

    @Test("Ready: everything done; without Apple Intelligence the summary is skipped and left out of the total")
    func ready() {
        #expect(steps(.ready).map(\.state) == [.done, .done, .done, .done])
        let noSummary = steps(.diarized, canSummarize: false)
        #expect(noSummary[3].state == .skipped)
        #expect(noSummary[3].detail == "Not available on \(Platform.thisDevice)")
        #expect(ProcessingSteps.overallFraction(noSummary, activeFraction: 0) == 1)
    }

    @Test("Failures land on the stage that failed; a skipped speaker pass is non-fatal")
    func failures() {
        let transcription = steps(.failed, failedStage: .transcribing, message: "No speech model")
        #expect(transcription.map(\.state) == [.done, .failed, .skipped, .skipped])
        #expect(transcription[1].detail == "No speech model")

        let voices = steps(.summarizing, failedStage: .diarizing, message: "Model missing")
        #expect(voices.map(\.state) == [.done, .done, .skipped, .active])

        let summary = steps(.ready, failedStage: .summarizing, message: "Free limit")
        #expect(summary[3].state == .failed)
        #expect(summary[3].detail == "Free limit")
    }

    @Test("Still recording: the first step is the active one")
    func recording() {
        #expect(steps(.recording).map(\.state) == [.active, .queued, .queued, .queued])
        #expect(steps(.recorded).map(\.state) == [.done, .queued, .queued, .queued])
    }
}
