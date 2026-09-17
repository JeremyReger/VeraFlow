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
    @State private var speakerController: SpeakerActionsController?

    private var speakers: [Speaker] { recording.speakers.sorted { $0.key < $1.key } }

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
        .modifier(OptionalSpeakerAlerts(controller: speakerController))
        .task {
            if speakerController == nil {
                speakerController = SpeakerActionsController(actions: SpeakerActions(context: modelContext))
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
            progressBanner(working: "Transcribing…", downloading: "Downloading the speech model (one time)…", systemImage: "waveform")
        case .diarizing:
            progressBanner(working: "Labeling speakers…", downloading: "Downloading the speaker-label models (one time)…", systemImage: "person.2.wave.2")
        case .failed where recording.failedStage == .transcribing || recording.failedStage == nil:
            banner(systemImage: "exclamationmark.triangle", text: recording.failureMessage ?? "Transcription failed.", tint: .red) {
                Button("Retry") {
                    Task { await services.pipeline.retry(recordingID: recording.id, from: .transcribing) }
                }
                .accessibilityIdentifier("transcript.retry")
            }
        default:
            if recording.failedStage == .diarizing, let message = recording.failureMessage {
                // Non-fatal (SPEC §6.3): the transcript is readable with one speaker.
                banner(systemImage: "person.2.slash", text: "Speaker labels couldn't be added: \(message)", tint: .orange) {
                    Button("Retry") {
                        Task { await services.pipeline.retry(recordingID: recording.id, from: .diarizing) }
                    }
                    .accessibilityIdentifier("transcript.retrySpeakers")
                }
            }
        }
    }

    private func progressBanner(working: String, downloading: String, systemImage: String) -> some View {
        let progress = appState?.pipelineProgress[recording.id]
        let preparing = progress?.isPreparingAssets ?? false
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: preparing ? "arrow.down.circle" : systemImage)
                Text(preparing ? downloading : working)
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

            if !speakers.isEmpty, let speakerController {
                speakersMenu(speakerController)
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

    /// Rename / Merge for every speaker (SPEC §10.3).
    private func speakersMenu(_ controller: SpeakerActionsController) -> some View {
        Menu {
            ForEach(speakers, id: \.key) { speaker in
                Menu(speaker.displayName) {
                    Button("Rename…", systemImage: "pencil") {
                        controller.beginRename(speaker)
                    }
                    if speakers.count > 1 {
                        Menu("Merge into…") {
                            ForEach(speakers.filter { $0.key != speaker.key }, id: \.key) { target in
                                Button(target.displayName) {
                                    controller.merge(speaker, into: target, in: recording)
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "person.2")
        }
        .accessibilityLabel("Speakers")
        .accessibilityIdentifier("transcript.speakers")
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
                if let speaker = speaker(for: segment.speakerKey) {
                    Button {
                        speakerController?.beginRename(speaker)
                    } label: {
                        Text(speaker.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(SpeakerPalette.color(for: speaker.colorIndex))
                    }
                    .buttonStyle(.plain)
                    .disabled(isEditing)
                    .accessibilityLabel("Speaker \(speaker.displayName), tap to rename")
                } else if let key = segment.speakerKey {
                    Text(key).font(.caption.weight(.semibold))
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
            if let speakerController, recording.stage.hasTranscript, recording.stage != .diarizing {
                Menu("Change speaker", systemImage: "person.crop.circle") {
                    ForEach(speakers, id: \.key) { speaker in
                        Button {
                            speakerController.assign(segment, to: speaker)
                        } label: {
                            if speaker.key == segment.speakerKey {
                                Label(speaker.displayName, systemImage: "checkmark")
                            } else {
                                Text(speaker.displayName)
                            }
                        }
                    }
                    Divider()
                    Button("New speaker", systemImage: "person.badge.plus") {
                        speakerController.assignToNewSpeaker(segment, in: recording)
                    }
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

    private func speaker(for key: String?) -> Speaker? {
        guard let key else { return nil }
        return recording.speakers.first { $0.key == key }
    }

    private func timestamp(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(0, seconds)).formatted(.time(pattern: seconds >= 3_600 ? .hourMinuteSecond : .minuteSecond))
    }
}

/// Rename and error alerts for the speaker controller, once it exists.
private struct OptionalSpeakerAlerts: ViewModifier {
    let controller: SpeakerActionsController?

    func body(content: Content) -> some View {
        if let controller {
            content.modifier(SpeakerAlerts(controller: controller))
        } else {
            content
        }
    }
}

private struct SpeakerAlerts: ViewModifier {
    @Bindable var controller: SpeakerActionsController

    func body(content: Content) -> some View {
        content
            .alert(
                "Rename speaker",
                isPresented: Binding(
                    get: { controller.renameTarget != nil },
                    set: { if !$0 { controller.cancelRename() } }
                ),
                presenting: controller.renameTarget
            ) { speaker in
                TextField("Name", text: $controller.renameDraft)
                Button("Save") { controller.commitRename(speaker) }
                Button("Cancel", role: .cancel) { controller.cancelRename() }
            } message: { _ in
                Text("The new name shows everywhere this speaker appears, including summaries.")
            }
            .alert(
                "Couldn't change speaker",
                isPresented: Binding(
                    get: { controller.errorMessage != nil },
                    set: { if !$0 { controller.errorMessage = nil } }
                )
            ) {
                Button("OK") { controller.errorMessage = nil }
            } message: {
                Text(controller.errorMessage ?? "")
            }
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
