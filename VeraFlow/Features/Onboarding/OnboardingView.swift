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
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
            .accessibilityIdentifier("onboarding.continue")
        }
        .task {
            await appState?.refreshCapabilities()
        }
    }

    // MARK: Pages

    private var whatItDoes: some View {
        OnboardingPage(systemImage: "waveform.circle.fill", title: "Your meetings, turned into a to-do list.") {
            VStack(alignment: .leading, spacing: 14) {
                Label("Record a meeting, lecture, or site walk-through", systemImage: "record.circle")
                Label("Get a transcript with speaker labels", systemImage: "text.alignleft")
                Label("Get a summary and action items you can send to Reminders", systemImage: "checklist")
            }
            .font(.body)
        }
    }

    private var privacy: some View {
        OnboardingPage(systemImage: "lock.iphone", title: "Everything stays on your iPhone.") {
            VStack(alignment: .leading, spacing: 14) {
                Label("No account, no cloud, no subscription", systemImage: "person.crop.circle.badge.xmark")
                Label("Transcripts and summaries are written on this iPhone", systemImage: "cpu")
                Label("The only downloads are Apple's speech model and the speaker-label model, once", systemImage: "arrow.down.circle")
            }
            .font(.body)
        }
    }

    private var microphone: some View {
        OnboardingPage(systemImage: "mic.circle.fill", title: "VeraFlow needs the microphone to record.") {
            VStack(spacing: 16) {
                Text("Audio is saved only on this iPhone.")
                    .foregroundStyle(.secondary)
                switch microphoneGranted {
                case nil:
                    Button("Allow microphone access") {
                        Task { microphoneGranted = await services.recorder.requestPermission() }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("onboarding.microphone")
                case true?:
                    Label("Microphone access allowed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case false?:
                    Text("Microphone access was not allowed. You can turn it on later in Settings → Privacy & Security → Microphone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
                }
            }
        }
    }

    @ViewBuilder
    private var assetDownload: some View {
        if let assetProgress {
            ProgressView(value: assetProgress) {
                Text(assetProgress < 1 ? "Downloading the speech model…" : "Speech model installed")
            }
        } else {
            Button("Download the speech model now") {
                Task { await downloadAssets() }
            }
            .buttonStyle(.bordered)
            Text("Otherwise it downloads with your first recording.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        if let assetMessage {
            Text(assetMessage).font(.footnote).foregroundStyle(.red)
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

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: systemImage)
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text(title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            content
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 28)
    }
}

private struct CapabilityRow: View {
    let ok: Bool
    let text: String

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: ok ? "checkmark.circle.fill" : "info.circle.fill")
                .foregroundStyle(ok ? .green : .orange)
        }
    }
}

#Preview {
    OnboardingView(onFinish: {})
        .environment(\.services, .fakes())
        .environment(AppState(services: .fakes()))
}
