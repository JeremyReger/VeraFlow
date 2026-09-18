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
        .background(VFColor.background)
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
        case .transcribing where !segments.isEmpty:
            progressBanner(working: "Transcribing…", downloading: "Downloading the speech model (one time)…", systemImage: "waveform")
        case .transcribing:
            // The processing card below carries the progress while there is nothing to read.
            EmptyView()
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
                    .accessibilityHidden(true)
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
                .accessibilityLabel(preparing ? downloading : working)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(VFColor.surface)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("transcript.progress")
    }

    private func banner<Action: View>(
        systemImage: String,
        text: String,
        tint: Color = .accentColor,
        @ViewBuilder action: () -> Action = { EmptyView() }
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage).foregroundStyle(tint).accessibilityHidden(true)
            Text(text).vfText(VFText.snippet, color: VFColor.textSecondary)
            Spacer(minLength: 0)
            action().buttonStyle(.bordered).controlSize(.small).frame(minHeight: 44)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(VFColor.surface)
    }

    // MARK: Header (search + edit)

    private var header: some View {
        HStack(spacing: 10) {
            VFField("Search transcript", text: $query, identifier: "transcript.search") {
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(VFColor.textTertiary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .disabled(isEditing)

            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(matchCountText)
                    .vfText(VFText.meta, color: VFColor.textTertiary)
            }

            if !speakers.isEmpty, let speakerController {
                speakersMenu(speakerController)
            }

            if recording.transcriptionEngine == .dictationTranscriber {
                Text("Standard accuracy")
                    .vfText(VFText.meta, color: VFColor.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .overlay { Capsule().strokeBorder(VFColor.borderStrong, lineWidth: VFMetric.hairline) }
                    .accessibilityLabel("Standard accuracy: this iPhone uses the standard speech recognizer.")
            }

            Button(isEditing ? "Done" : "Edit") {
                if isEditing { commitEdits() } else { drafts = [:] }
                isEditing.toggle()
            }
            .vfText(VFText.rowLabel, color: VFColor.accent)
            .frame(minHeight: VFMetric.minHit)
            .accessibilityIdentifier("transcript.edit")
        }
        .padding(.horizontal, VFSpace.gutterTight)
        .padding(.vertical, 8)
        // Silent state changes get spoken (A-4).
        .onChange(of: matches.count) { _, _ in
            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                AccessibilityNotification.Announcement(matchCountText).post()
            }
        }
        .onChange(of: recording.stage) { _, stage in
            AccessibilityNotification.Announcement(stage.displayName).post()
        }
    }

    /// Rename / Merge for every speaker (SPEC §10.3).
    private func speakersMenu(_ controller: SpeakerActionsController) -> some View {
        Menu {
            Button("Re-run speaker labels", systemImage: "arrow.clockwise") {
                Task { await services.pipeline.retry(recordingID: recording.id, from: .diarizing) }
            }
            .disabled(recording.stage.isProcessing)
            Divider()
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
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(VFColor.iconPrimary)
                .frame(width: VFMetric.iconButton, height: VFMetric.iconButton)
                .background(VFColor.surface, in: Circle())
                .overlay { Circle().strokeBorder(VFColor.border, lineWidth: VFMetric.hairline) }
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
                LazyVStack(alignment: .leading, spacing: VFSpace.listGap) {
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
                .padding(.horizontal, VFSpace.gutterTight)
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
        let segmentSpeaker = speaker(for: segment.speakerKey)
        let speakerName = segmentSpeaker?.displayName ?? segment.speakerKey.map(SpokenFormat.speakerName(forKey:)) ?? ""
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let speaker = segmentSpeaker {
                    // Dot + name + timecode + "NAME?" while the label is still the default (spec §4).
                    VFSpeakerTag(
                        name: speaker.displayName,
                        index: speaker.colorIndex,
                        timecode: timestamp(segment.start),
                        needsName: Self.isDefaultName(speaker.displayName)
                    ) {
                        guard !isEditing else { return }
                        speakerController?.beginRename(speaker)
                    }
                } else {
                    // Bold while playing, so the current paragraph isn't marked by colour alone (A-14).
                    Text(timestamp(segment.start))
                        .vfText(VFText.meta, color: isCurrent ? VFColor.accent : VFColor.textTertiary)
                        .fontWeight(isCurrent ? .bold : .regular)
                    if let key = segment.speakerKey {
                        Text(SpokenFormat.speakerName(forKey: key).uppercased())
                            .vfText(VFText.speakerLabel, color: VFColor.textSecondary)
                    }
                }
                if segment.isEdited {
                    Image(systemName: "pencil")
                        .font(.caption2)
                        .foregroundStyle(VFColor.textTertiary)
                        .accessibilityLabel("Edited")
                }
            }
            if isEditing {
                TextField("Paragraph text", text: draftBinding(for: segment), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Paragraph at \(SpokenFormat.duration(segment.start)), \(speakerName)")
            } else {
                Text(TranscriptText.attributed(
                    text: segment.text,
                    words: wordIndex == nil ? [] : segment.words,
                    highlightedWord: wordIndex
                ))
                .vfText(VFText.transcriptBody)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, VFSpace.cardPaddingH)
        .padding(.vertical, 12)
        .background(paragraphBackground(isCurrent: isCurrent, isMatch: isMatch), in: RoundedRectangle(cornerRadius: VFRadius.block, style: .continuous))
        .overlay {
            // The block being played gets a tinted fill and a border, not a left bar (spec §4).
            RoundedRectangle(cornerRadius: VFRadius.block, style: .continuous)
                .strokeBorder(isCurrent ? VFColor.nowPlayingBorder : .clear, lineWidth: VFMetric.hairline)
        }
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
                    revert(segment)
                }
            }
            if let speakerController, canChangeSpeaker {
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
        // One VoiceOver element per paragraph, with every long-press action available from the
        // actions rotor so Switch Control and Full Keyboard Access can reach them too (A-3).
        // While editing the text field stays its own element.
        .accessibilityElement(children: isEditing ? .contain : .combine)
        .accessibilityLabel(isEditing ? "" : "\(speakerName), \(SpokenFormat.duration(segment.start))")
        .accessibilityValue(isEditing ? "" : paragraphValue(segment, isCurrent: isCurrent, isMatch: isMatch))
        .accessibilityAddTraits(isEditing ? [] : .isButton)
        .accessibilityHint(isEditing ? "" : "Seeks playback to this paragraph")
        .accessibilityActions {
            Button("Play from here") {
                player.seek(to: segment.start)
                player.play()
            }
            if segment.isEdited {
                Button("Revert to transcribed text") { revert(segment) }
            }
            if let speaker = segmentSpeaker {
                Button("Rename \(speaker.displayName)") { speakerController?.beginRename(speaker) }
            }
            if let speakerController, canChangeSpeaker {
                ForEach(speakers.filter { $0.key != segment.speakerKey }, id: \.key) { other in
                    Button("Change speaker to \(other.displayName)") { speakerController.assign(segment, to: other) }
                }
                Button("New speaker") { speakerController.assignToNewSpeaker(segment, in: recording) }
            }
        }
        .accessibilityIdentifier("transcript.paragraph.\(segment.index)")
    }

    private var canChangeSpeaker: Bool {
        recording.stage.hasTranscript && recording.stage != .diarizing
    }

    private func revert(_ segment: TranscriptSegment) {
        TranscriptText.revert(segment)
        drafts[segment.index] = nil
        try? modelContext.save()
    }

    private func paragraphValue(_ segment: TranscriptSegment, isCurrent: Bool, isMatch: Bool) -> String {
        var parts: [String] = []
        if isCurrent { parts.append("Now playing") }
        if isMatch { parts.append("Search match") }
        if segment.isEdited { parts.append("Edited") }
        parts.append(segment.text)
        return parts.joined(separator: ", ")
    }

    private func paragraphBackground(isCurrent: Bool, isMatch: Bool) -> Color {
        if isCurrent { return VFColor.nowPlayingFill }
        if isMatch { return VFColor.accent.opacity(0.12) }
        return .clear
    }

    /// "Speaker 2" and the like: the diarizer's label, not a name the user gave.
    static func isDefaultName(_ name: String) -> Bool {
        let parts = name.split(separator: " ")
        return parts.count == 2 && parts[0] == "Speaker" && Int(parts[1]) != nil
    }

    private var emptyState: some View {
        Group {
            switch recording.stage {
            case .recording, .recorded, .transcribing, .failed:
                ScrollView {
                    ProcessingCard(
                        recording: recording,
                        progress: appState?.pipelineProgress[recording.id],
                        canSummarize: appState?.capabilities?.canSummarize ?? true
                    )
                    .padding(.horizontal, VFSpace.gutterTight)
                    .padding(.vertical, VFSpace.sectionGap)
                }
            default:
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "waveform.slash")
                        .font(.system(size: 34))
                        .foregroundStyle(VFColor.textTertiary)
                        .accessibilityHidden(true)
                    Text("No speech detected")
                        .vfText(VFText.cardTitle)
                        .accessibilityAddTraits(.isHeader)
                    Text("The recording was transcribed but no words were found.")
                        .vfText(VFText.body, color: VFColor.textSecondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .padding(.horizontal, VFSpace.gutter + 8)
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
struct OptionalSpeakerAlerts: ViewModifier {
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
