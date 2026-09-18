import SwiftUI

/// The processing state the old build hid (design spec §4 Processing): a determinate bar and
/// the four steps, with honest copy about what keeps going in the background.
struct ProcessingCard: View {
    let recording: Recording
    let progress: PipelineProgress?
    let canSummarize: Bool

    private var steps: [ProcessingStep] {
        ProcessingSteps.steps(
            stage: recording.stage,
            failedStage: recording.failedStage,
            failureMessage: recording.failureMessage,
            fraction: progress?.fraction ?? 0,
            isPreparingAssets: progress?.isPreparingAssets ?? false,
            canSummarize: canSummarize
        )
    }

    var body: some View {
        let rows = steps
        let overall = ProcessingSteps.overallFraction(rows, activeFraction: progress?.fraction ?? 0)
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text(recording.stage == .failed ? "Processing stopped" : "Working on it")
                    .vfText(VFText.cardTitle)
                    .accessibilityAddTraits(.isHeader)
                ProgressView(value: overall)
                    .tint(recording.stage == .failed ? VFColor.danger : VFColor.accent)
                    .accessibilityLabel("Processing")
                    .accessibilityValue("\(Int((overall * 100).rounded())) percent")
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { position, step in
                    if position > 0 { VFHairline() }
                    row(step)
                }
            }
            Text("This runs on your iPhone. Transcription keeps going in the background; speaker labels and the summary finish while the app is open.")
                .vfText(VFText.reassurance, color: VFColor.textSecondary)
        }
        .padding(VFSpace.cardPaddingH)
        .background(VFColor.surface, in: RoundedRectangle(cornerRadius: VFRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: VFRadius.card, style: .continuous)
                .strokeBorder(VFColor.border, lineWidth: VFMetric.hairline)
        }
        .accessibilityIdentifier("processing.card")
    }

    private func row(_ step: ProcessingStep) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            glyph(step.state)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(step.title)
                    .vfText(VFText.rowLabel, color: step.state == .queued || step.state == .skipped ? VFColor.textTertiary : VFColor.textPrimary)
                if let detail = step.detail {
                    Text(detail)
                        .vfText(VFText.meta, color: step.state == .failed ? VFColor.danger : VFColor.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([Self.spoken(step.state), step.title, step.detail].compactMap { $0 }.joined(separator: ", "))
    }

    @ViewBuilder
    private func glyph(_ state: ProcessingStep.State) -> some View {
        switch state {
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(VFColor.success)
        case .active:
            ProgressView().controlSize(.small).tint(VFColor.accent)
        case .queued:
            Image(systemName: "circle").foregroundStyle(VFColor.borderStrong)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(VFColor.danger)
        case .skipped:
            Image(systemName: "minus.circle").foregroundStyle(VFColor.textTertiary)
        }
    }

    private static func spoken(_ state: ProcessingStep.State) -> String {
        switch state {
        case .done: "Done"
        case .active: "In progress"
        case .queued: "Waiting"
        case .failed: "Failed"
        case .skipped: "Skipped"
        }
    }
}
