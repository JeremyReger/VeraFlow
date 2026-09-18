import SwiftUI

/// First launch (SPEC §4.1): what it does → everything stays on your iPhone → microphone →
/// what this iPhone can do (honest Apple Intelligence messaging, optional speech-model download).
struct OnboardingView: View {
    var onFinish: () -> Void
    @Environment(\.services) private var services
    @Environment(AppState.self) private var appState: AppState?
    @State private var page = 0
    @State private var microphoneGranted: Bool?
    @State private var assetProgress: Double?
    @State private var assetMessage: String?

    private let pageCount = 4

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                whatItDoes.tag(0)
                privacy.tag(1)
                microphone.tag(2)
                capabilities.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button(page == pageCount - 1 ? "Get started" : "Continue") {
                if page < pageCount - 1 {
                    withAnimation { page += 1 }
                } else {
                    onFinish()
                }
            }
            .buttonStyle(VFPrimaryPillStyle())
            .padding(.horizontal, VFSpace.gutter)
            .padding(.bottom, VFSpace.bottomInset)
            .accessibilityIdentifier("onboarding.continue")
        }
        .background(VFColor.background.ignoresSafeArea())
        .task {
            await appState?.refreshCapabilities()
        }
    }

    // MARK: Pages

    private var whatItDoes: some View {
        OnboardingPage(systemImage: "waveform.circle.fill", title: "Your meetings, turned into a to-do list.") {
            VStack(alignment: .leading, spacing: 14) {
                point("Record a meeting, lecture, or site walk-through", systemImage: "record.circle")
                point("Get a transcript with speaker labels", systemImage: "text.alignleft")
                point("Get a summary and action items you can send to Reminders", systemImage: "checklist")
            }
        }
    }

    private var privacy: some View {
        OnboardingPage(systemImage: "lock.iphone", title: "Everything stays on your iPhone.") {
            VStack(alignment: .leading, spacing: 14) {
                point("No account, no cloud, no subscription", systemImage: "person.crop.circle.badge.xmark")
                point("Transcripts and summaries are written on this iPhone", systemImage: "cpu")
                point("The only downloads are Apple's speech model and the speaker-label model, once", systemImage: "arrow.down.circle")
            }
        }
    }

    private var microphone: some View {
        OnboardingPage(systemImage: "mic.circle.fill", title: "VeraFlow needs the microphone to record.") {
            VStack(spacing: 16) {
                Text("Audio is saved only on this iPhone.")
                    .vfText(VFText.body, color: VFColor.textSecondary)
                    .multilineTextAlignment(.center)
                switch microphoneGranted {
                case nil:
                    Button("Allow microphone access") {
                        Task { microphoneGranted = await services.recorder.requestPermission() }
                    }
                    .buttonStyle(VFSecondaryPillStyle())
                    .accessibilityIdentifier("onboarding.microphone")
                case true?:
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(VFColor.success)
                            .accessibilityHidden(true)
                        Text("Microphone access allowed")
                            .vfText(VFText.rowLabel)
                    }
                    .accessibilityElement(children: .combine)
                case false?:
                    Text("Microphone access was not allowed. You can turn it on later in Settings → Privacy & Security → Microphone.")
                        .vfText(VFText.snippet, color: VFColor.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private var capabilities: some View {
        OnboardingPage(systemImage: "iphone.gen3", title: "What this iPhone can do") {
            VStack(alignment: .leading, spacing: 14) {
                if let capabilities = appState?.capabilities {
                    CapabilityRow(
                        ok: capabilities.canTranscribe,
                        text: capabilities.transcriptionEngine == .dictationTranscriber
                            ? "Transcripts work, at standard accuracy on this iPhone."
                            : capabilities.canTranscribe ? "Transcripts work on this iPhone." : "Transcription isn't available on this iPhone."
                    )
                    CapabilityRow(ok: true, text: "Speaker labels are added on this iPhone. The model downloads once, when first needed.")
                    CapabilityRow(
                        ok: capabilities.canSummarize,
                        text: capabilities.canSummarize
                            ? "AI summaries and action items are available."
                            : Self.summaryMessage(capabilities.summarization)
                    )
                    if capabilities.transcriptionAssets == .downloadRequired {
                        assetDownload
                    }
                } else {
                    ProgressView("Checking…")
                        .tint(VFColor.accent)
                }
            }
        }
    }

    /// One bullet of an onboarding page: accent glyph, sans body.
    private func point(_ text: String, systemImage: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(VFColor.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text).vfText(VFText.body, color: VFColor.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var assetDownload: some View {
        if let assetProgress {
            ProgressView(value: assetProgress) {
                Text(assetProgress < 1 ? "Downloading the speech model…" : "Speech model installed")
                    .vfText(VFText.snippet, color: VFColor.textSecondary)
            }
            .tint(VFColor.accent)
        } else {
            Button("Download the speech model now") {
                Task { await downloadAssets() }
            }
            .buttonStyle(VFSecondaryPillStyle())
            Text("Otherwise it downloads with your first recording.")
                .vfText(VFText.snippet, color: VFColor.textTertiary)
        }
        if let assetMessage {
            Text(assetMessage).vfText(VFText.snippet, color: VFColor.danger)
        }
    }

    private func downloadAssets() async {
        assetProgress = 0
        do {
            try await services.transcription.prepareAssets(for: .current) { fraction in
                Task { @MainActor in assetProgress = fraction }
            }
            assetProgress = 1
            await appState?.refreshCapabilities()
        } catch {
            assetProgress = nil
            assetMessage = PipelineFailure.message(for: error)
        }
    }

    /// SPEC §4.1 / §11.1 copy for each reason. No medical/legal claims, no promises.
    static func summaryMessage(_ availability: SummarizationAvailability) -> String {
        switch availability {
        case .available:
            return "AI summaries and action items are available."
        case .deviceNotEligible:
            return "Transcripts work on this iPhone; AI summaries need an Apple Intelligence–capable iPhone."
        case .appleIntelligenceNotEnabled:
            return "Turn on Apple Intelligence in Settings to get AI summaries. Transcripts work either way."
        case .modelNotReady:
            return "Apple Intelligence is still downloading. Summaries will work once it's ready."
        case .unknown:
            return "AI summaries aren't available right now. Transcripts still work."
        }
    }
}

private struct OnboardingPage<Content: View>: View {
    let systemImage: String
    let title: String
    @ViewBuilder let content: Content
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 64

    var body: some View {
        // Scrolls so large text sizes never clip the page (A-15).
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: systemImage)
                    .font(.system(size: iconSize, weight: .light))
                    .foregroundStyle(VFColor.accent)
                    .accessibilityHidden(true)
                    .padding(.top, 48)
                Text(title)
                    .vfText(VFText.recordingTitle)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                content
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct CapabilityRow: View {
    let ok: Bool
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: ok ? "checkmark.circle.fill" : "info.circle.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(ok ? VFColor.success : VFColor.textTertiary)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text).vfText(VFText.body, color: VFColor.textPrimary)
        }
        // The icon carries the state for sighted users; the label carries it for VoiceOver (A-21).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((ok ? "Available: " : "Note: ") + text)
    }
}

#Preview {
    OnboardingView(onFinish: {})
        .environment(\.services, .fakes())
        .environment(AppState(services: .fakes()))
}
