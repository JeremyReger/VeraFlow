#if DEBUG
import SwiftData
import SwiftUI

/// Debug-only screen (SPEC §9.4): runs Apple Speech and Parakeet on one recording, shows time,
/// speed, word count, and WER against a pasted reference, and lets the tester pick which
/// engine the pipeline uses for new transcripts. Not compiled into release builds.
struct TranscriptionBenchmarkView: View {
    @Environment(\.services) private var services
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]
    @State private var model = TranscriptionBenchmarkModel()
    @State private var selectedID: UUID?
    @State private var reference = ""
    @State private var engineChoice = EngineSelectingTranscriptionService.choice()

    private var selected: Recording? {
        recordings.first { $0.id == selectedID }
    }

    var body: some View {
        Form {
            Section {
                Picker("Engine", selection: $engineChoice) {
                    ForEach(EngineSelectingTranscriptionService.Choice.allCases, id: \.self) { choice in
                        Text(choice.displayName).tag(choice)
                    }
                }
                .onChange(of: engineChoice) { _, choice in
                    EngineSelectingTranscriptionService.setChoice(choice)
                }
            } header: {
                Text("Engine for new transcripts")
            } footer: {
                Text("Applies to recordings transcribed from now on. Both engines run entirely on \(Platform.thisDevice); Parakeet downloads its model once.")
            }

            Section("Recording") {
                Picker("Recording", selection: $selectedID) {
                    Text("Choose…").tag(UUID?.none)
                    ForEach(recordings) { recording in
                        Text("\(recording.title) · \(durationText(recording.duration))")
                            .tag(Optional(recording.id))
                    }
                }
            }

            Section {
                TextEditor(text: $reference)
                    .frame(minHeight: 120)
                    .font(.body)
                    .autocorrectionDisabled()
            } header: {
                Text("Reference transcript (optional)")
            } footer: {
                Text("Paste the hand-corrected text to get a word error rate. Punctuation and case are ignored.")
            }

            Section {
                Button(model.isRunning ? "Running…" : "Run both engines") {
                    guard let recording = selected else { return }
                    let url = services.storage.audioURL(for: recording.id, fileName: recording.audioFileName)
                    let locale = Locale(identifier: recording.localeIdentifier)
                    let engines = services.benchmarkEngines
                    let reference = reference
                    Task {
                        await model.run(
                            engines: engines,
                            fixtureName: recording.title,
                            fileURL: url,
                            audioSeconds: recording.duration,
                            locale: locale,
                            reference: reference
                        )
                    }
                }
                .disabled(selected == nil || model.isRunning)

                if model.isRunning {
                    ForEach(services.benchmarkEngines.map(\.name), id: \.self) { name in
                        ProgressView(value: model.progress[name] ?? 0) {
                            Text(name)
                        }
                    }
                }
            } footer: {
                Text("Keep the app in the foreground while it runs. A 10-minute file can take a few minutes per engine.")
            }

            if !model.outcomes.isEmpty {
                Section("Results") {
                    ForEach(model.outcomes, id: \.engineName) { outcome in
                        outcomeRow(outcome)
                    }
                    ShareLink(item: model.report) {
                        Label("Share report", systemImage: "square.and.arrow.up")
                    }
                }
                ForEach(model.outcomes, id: \.engineName) { outcome in
                    if !outcome.transcript.isEmpty {
                        Section("\(outcome.engineName) transcript") {
                            Text(outcome.transcript)
                                .font(.footnote)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .navigationTitle("Transcription benchmark")
        .toolbarTitleDisplayMode(.inline)
    }

    private func outcomeRow(_ outcome: TranscriptionBenchmark.Outcome) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(outcome.engineName).font(.headline)
            if let message = outcome.errorMessage {
                Text(message).foregroundStyle(.red).font(.footnote)
            } else {
                HStack(spacing: 12) {
                    Label(String(format: "%.1f s", outcome.seconds), systemImage: "clock")
                    Label(String(format: "%.1f×", outcome.realTimeFactor), systemImage: "hare")
                    Label("\(outcome.wordCount)", systemImage: "text.word.spacing")
                    if let score = outcome.wordErrorRate {
                        Label(String(format: "WER %.1f%%", score.rate * 100), systemImage: "checkmark.seal")
                    }
                }
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(0, seconds)).formatted(.time(pattern: seconds >= 3_600 ? .hourMinuteSecond : .minuteSecond))
    }
}

#Preview {
    NavigationStack {
        TranscriptionBenchmarkView()
    }
    .modelContainer(PreviewData.container())
    .environment(\.services, .fakes())
}
#endif
