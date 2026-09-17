import SwiftData
import SwiftUI

/// Transcript tab (SPEC §4.4): timestamped paragraphs, synced highlight during playback,
/// tap-to-seek, edit mode, search, and the processing status for this recording.
struct TranscriptTab: View {
    let recording: Recording
    let player: AudioPlayerController
    @Environment(\.services) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState: AppState?
    @State private var query = ""
    @State private var isEditing = false
    /// Edits in progress, keyed by segment index; applied on Done.
    @State private var drafts: [Int: String] = [:]

    private var segments: [TranscriptSegment] { recording.orderedSegments }

    private var matches: [Int] {
        TranscriptText.matches(query: query, in: segments.map(\.text))
    }

    private var position: TranscriptPosition? {
        guard !segments.isEmpty else { return nil }
        return TranscriptCursor.position(
            at: player.currentTime,
            starts: segments.map(\.start),
            words: { segments[$0].words },
            wordsAreCurrent: { !segments[$0].isEdited }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            statusBanner
            if !segments.isEmpty {
                header
                paragraphList
            } else {
                emptyState
            }
        }
    }

    // MARK: Status

    @ViewBuilder
    private var statusBanner: some View {
        switch recording.stage {
        case .recording:
            banner(systemImage: "record.circle", text: "Still recording.")
        case .recorded:
            banner(systemImage: "waveform", text: "Not transcribed yet.") {
                Button("Transcribe") {
                    Task { await services.pipeline.enqueue(recordingID: recording.id) }
                }
                .accessibilityIdentifier("transcript.transcribe")
            }
        case .transcribing:
            progressBanner
        case .failed where recording.failedStage == .transcribing || recording.failedStage == nil:
            banner(systemImage: "exclamationmark.triangle", text: recording.failureMessage ?? "Transcription failed.", tint: .red) {
                Button("Retry") {
                    Task { await services.pipeline.retry(recordingID: recording.id, from: .transcribing) }
                }
                .accessibilityIdentifier("transcript.retry")
            }
        default:
            EmptyView()
        }
    }

    private var progressBanner: some View {
        let progress = appState?.pipelineProgress[recording.id]
        let preparing = progress?.isPreparingAssets ?? false
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: preparing ? "arrow.down.circle" : "waveform")
                Text(preparing ? "Downloading the speech model (one time)…" : "Transcribing…")
                Spacer()
                if let fraction = progress?.fraction, fraction > 0 {
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .font(.footnote)
            ProgressView(value: progress?.fraction ?? 0)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
        .accessibilityIdentifier("transcript.progress")
    }

    private func banner<Action: View>(
        systemImage: String,
        text: String,
        tint: Color = .accentColor,
        @ViewBuilder action: () -> Action = { EmptyView() }
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage).foregroundStyle(tint)
            Text(text).font(.footnote)
            Spacer(minLength: 0)
            action().buttonStyle(.bordered).controlSize(.small)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: Header (search + edit)

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search transcript", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("transcript.search")
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(.secondarySystemBackground), in: Capsule())
            .disabled(isEditing)

            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(matchCountText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if recording.transcriptionEngine == .dictationTranscriber {
                Text("Standard accuracy")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.tertiarySystemFill), in: Capsule())
                    .accessibilityHint("This iPhone uses the standard speech recognizer.")
            }

            Button(isEditing ? "Done" : "Edit") {
                if isEditing { commitEdits() } else { drafts = [:] }
                isEditing.toggle()
            }
            .fontWeight(isEditing ? .semibold : .regular)
            .accessibilityIdentifier("transcript.edit")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var matchCountText: String {
        let count = matches.count
        return count == 1 ? "1 match" : "\(count) matches"
    }

    // MARK: Paragraphs

    private var paragraphList: some View {
        let current = position
        let matched = Set(matches)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(segments, id: \.index) { segment in
                        paragraph(
                            segment,
                            isCurrent: current?.segmentIndex == segment.index,
                            wordIndex: current?.segmentIndex == segment.index ? current?.wordIndex : nil,
                            isMatch: matched.contains(segment.index)
                        )
                        .id(segment.index)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: current?.segmentIndex) { _, index in
                // Follow the playhead only while playing and not busy searching or editing.
                guard let index, player.isPlaying, !isEditing, matches.isEmpty else { return }
                withAnimation { proxy.scrollTo(index, anchor: .center) }
            }
            .onChange(of: matches.first) { _, first in
                guard let first else { return }
                withAnimation { proxy.scrollTo(first, anchor: .top) }
            }
        }
    }

    private func paragraph(_ segment: TranscriptSegment, isCurrent: Bool, wordIndex: Int?, isMatch: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(timestamp(segment.start))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
                if let name = speakerName(for: segment.speakerKey) {
                    Text(name).font(.caption.weight(.semibold))
                }
                if segment.isEdited {
                    Image(systemName: "pencil")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Edited")
                }
            }
            if isEditing {
                TextField("Paragraph text", text: draftBinding(for: segment), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
            } else {
                Text(TranscriptText.attributed(
                    text: segment.text,
                    words: wordIndex == nil ? [] : segment.words,
                    highlightedWord: wordIndex
                ))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(paragraphBackground(isCurrent: isCurrent, isMatch: isMatch), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isEditing else { return }
            player.seek(to: segment.start)
        }
        .contextMenu {
            Button("Play from here", systemImage: "play") {
                player.seek(to: segment.start)
                player.play()
            }
            if segment.isEdited {
                Button("Revert to transcribed text", systemImage: "arrow.uturn.backward") {
                    TranscriptText.revert(segment)
                    drafts[segment.index] = nil
                    try? modelContext.save()
                }
            }
        }
        .accessibilityIdentifier("transcript.paragraph.\(segment.index)")
    }

    private func paragraphBackground(isCurrent: Bool, isMatch: Bool) -> Color {
        if isMatch { return .yellow.opacity(0.22) }
        if isCurrent { return .accentColor.opacity(0.10) }
        return .clear
    }

    private var emptyState: some View {
        Group {
            switch recording.stage {
            case .recording, .recorded, .transcribing, .failed:
                Spacer()
            default:
                ContentUnavailableView(
                    "No speech detected",
                    systemImage: "waveform.slash",
                    description: Text("The recording was transcribed but no words were found.")
                )
            }
        }
    }

    // MARK: Editing

    private func draftBinding(for segment: TranscriptSegment) -> Binding<String> {
        let index = segment.index
        return Binding(
            get: { drafts[index] ?? segment.text },
            set: { drafts[index] = $0 }
        )
    }

    private func commitEdits() {
        var changed = false
        for segment in segments {
            if let draft = drafts[segment.index] {
                changed = TranscriptText.commit(draft, to: segment) || changed
            }
        }
        drafts = [:]
        if changed {
            try? modelContext.save()
        }
    }

    // MARK: Helpers

    private func speakerName(for key: String?) -> String? {
        guard let key else { return nil }
        return recording.speakers.first { $0.key == key }?.displayName ?? key
    }

    private func timestamp(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(0, seconds)).formatted(.time(pattern: seconds >= 3_600 ? .hourMinuteSecond : .minuteSecond))
    }
}

#Preview {
    let recording = PreviewData.sampleRecording()
    NavigationStack {
        TranscriptTab(recording: recording, player: AudioPlayerController())
    }
    .modelContainer(PreviewData.container())
    .environment(\.services, .fakes())
    .environment(AppState(services: .fakes()))
}
