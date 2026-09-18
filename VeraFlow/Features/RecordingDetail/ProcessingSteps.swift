import Foundation

/// One row of the processing card (design spec §4 Processing).
struct ProcessingStep: Equatable, Sendable, Identifiable {
    enum State: Equatable, Sendable {
        case done
        case active
        case queued
        case failed
        /// Won't run on this iPhone (no Apple Intelligence) or was skipped after a non-fatal failure.
        case skipped
    }

    let id: String
    let title: String
    let state: State
    let detail: String?
}

/// Turns a recording's stage into the four steps the card shows. Pure, so it's testable.
enum ProcessingSteps {
    static func steps(
        stage: PipelineStage,
        failedStage: PipelineStage?,
        failureMessage: String?,
        fraction: Double,
        isPreparingAssets: Bool,
        canSummarize: Bool
    ) -> [ProcessingStep] {
        let order: [PipelineStage] = [.recording, .recorded, .transcribing, .transcribed, .diarizing, .diarized, .summarizing, .ready]
        let position = order.firstIndex(of: stage) ?? -1
        func reached(_ target: PipelineStage) -> Bool {
            guard let index = order.firstIndex(of: target) else { return false }
            return position >= index
        }
        let percent = fraction > 0 ? (fraction * 100).rounded() : nil
        let percentText = percent.map { "\(Int($0)) percent" }
        let failed = stage == .failed

        let saved = ProcessingStep(
            id: "saved",
            title: "Audio saved",
            state: stage == .recording ? .active : .done,
            detail: nil
        )

        let transcribe: ProcessingStep
        if failed, failedStage == .transcribing || failedStage == nil {
            transcribe = ProcessingStep(id: "transcribe", title: "Transcribing", state: .failed, detail: failureMessage)
        } else if stage == .transcribing {
            transcribe = ProcessingStep(
                id: "transcribe", title: "Transcribing", state: .active,
                detail: isPreparingAssets ? "Downloading the speech model, one time" : percentText
            )
        } else if failed || reached(.transcribed) {
            transcribe = ProcessingStep(id: "transcribe", title: "Transcribed", state: .done, detail: nil)
        } else {
            transcribe = ProcessingStep(id: "transcribe", title: "Transcribing", state: .queued, detail: nil)
        }

        let voices: ProcessingStep
        if failedStage == .diarizing, stage != .diarizing {
            // Non-fatal (SPEC §6.3): the transcript reads with one speaker.
            voices = ProcessingStep(id: "voices", title: "Telling the voices apart", state: failed ? .failed : .skipped, detail: failureMessage)
        } else if stage == .diarizing {
            voices = ProcessingStep(
                id: "voices", title: "Telling the voices apart", state: .active,
                detail: isPreparingAssets ? "Downloading the speaker-label models, one time" : percentText
            )
        } else if reached(.diarized) {
            voices = ProcessingStep(id: "voices", title: "Voices labeled", state: .done, detail: nil)
        } else if failed {
            voices = ProcessingStep(id: "voices", title: "Telling the voices apart", state: .skipped, detail: nil)
        } else {
            voices = ProcessingStep(id: "voices", title: "Telling the voices apart", state: .queued, detail: nil)
        }

        let summary: ProcessingStep
        if !canSummarize {
            summary = ProcessingStep(id: "summary", title: "Writing the summary", state: .skipped, detail: "Not available on this iPhone")
        } else if failedStage == .summarizing, stage == .ready || failed {
            summary = ProcessingStep(id: "summary", title: "Writing the summary", state: .failed, detail: failureMessage)
        } else if stage == .summarizing {
            summary = ProcessingStep(id: "summary", title: "Writing the summary", state: .active, detail: percentText)
        } else if stage == .ready {
            summary = ProcessingStep(id: "summary", title: "Summary written", state: .done, detail: nil)
        } else if failed {
            summary = ProcessingStep(id: "summary", title: "Writing the summary", state: .skipped, detail: nil)
        } else {
            summary = ProcessingStep(id: "summary", title: "Writing the summary", state: .queued, detail: nil)
        }

        return [saved, transcribe, voices, summary]
    }

    /// Progress across the steps that will run: finished steps count in full, the active one by
    /// `fraction`. Skipped steps are left out of the total.
    static func overallFraction(_ steps: [ProcessingStep], activeFraction: Double) -> Double {
        let counted = steps.filter { $0.state != .skipped }
        guard !counted.isEmpty else { return 0 }
        var total = 0.0
        for step in counted {
            switch step.state {
            case .done: total += 1
            case .active: total += min(max(activeFraction, 0), 1)
            case .queued, .failed, .skipped: break
            }
        }
        return total / Double(counted.count)
    }
}
