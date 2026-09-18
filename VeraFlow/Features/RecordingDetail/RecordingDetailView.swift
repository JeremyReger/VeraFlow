import SwiftData
import SwiftUI

/// Summary / Transcript / Audio tabs for one recording (SPEC §4.4). The full Audio tab
/// (waveform, speed) lands in M9.
struct RecordingDetailView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case summary
        case transcript
        case audio

        var id: String { rawValue }

        var title: String {
            switch self {
            case .summary: "Summary"
            case .transcript: "Transcript"
            case .audio: "Audio"
            }
        }
    }

    let recording: Recording
    @Environment(\.services) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState: AppState?
    @Query private var allRecordings: [Recording]
    @State private var tab: Tab
    @State private var player = AudioPlayerController()
    @State private var controller: RecordingActionsController?
    @State private var exportController: ExportController?
    @State private var remindersRecord: SummaryRecord?
    @State private var showsPaywall = false

    /// Explicit because `@Query` makes the synthesized initializer private. Opens on the Summary
    /// when there is one, otherwise on the Transcript.
    init(recording: Recording) {
        self.recording = recording
        _tab = State(initialValue: recording.currentSummary == nil ? .transcript : .summary)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $tab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .accessibilityIdentifier("detail.tabs")

            switch tab {
            case .summary:
                SummaryTab(recording: recording, player: player)
            case .transcript:
                TranscriptTab(recording: recording, player: player)
            case .audio:
                audioTab
            }
        }
        .safeAreaInset(edge: .bottom) {
            if tab != .audio {
                AudioPlayerView(player: player)
                    .padding(.horizontal)
                    .background(.bar)
            }
        }
        .navigationTitle(recording.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let exportController {
                ToolbarItem(placement: .primaryAction) {
                    Menu("Share", systemImage: "square.and.arrow.up") {
                        ExportMenuItems(
                            recording: recording,
                            controller: exportController,
                            onSendToReminders: { remindersRecord = recording.currentSummary },
                            onLocked: { showsPaywall = true },
                            isUnlocked: appState?.isUnlocked ?? false
                        )
                    }
                    .accessibilityIdentifier("detail.share")
                }
            }
            if let controller {
                ToolbarItem(placement: .primaryAction) {
                    Menu("Actions", systemImage: "ellipsis.circle") {
                        RecordingMenuItems(recording: recording, controller: controller)
                    }
                    .accessibilityIdentifier("detail.actions")
                }
            }
        }
        .modifier(OptionalRecordingActions(controller: controller, allTags: LibraryFilter.allTags(in: allRecordings)))
        .modifier(OptionalExportPresentation(controller: exportController))
        .sheet(item: $remindersRecord) { record in
            RemindersSheet(recording: recording, record: record)
        }
        .sheet(isPresented: $showsPaywall) {
            PaywallView()
        }
        .task {
            if controller == nil {
                let actions = LibraryActions(context: modelContext, services: services)
                let controller = RecordingActionsController(actions: actions)
                controller.onDeleted = { _ in dismiss() }
                self.controller = controller
            }
            if exportController == nil {
                exportController = ExportController(services: services)
            }
            player.load(url: services.storage.audioURL(for: recording.id, fileName: recording.audioFileName), title: recording.title)
        }
        .onDisappear { player.stop() }
    }

    private var audioTab: some View {
        List {
            Section("Audio") {
                AudioPlayerView(player: player)
            }
            if !recording.bookmarks.isEmpty {
                Section("Bookmarks") {
                    ForEach(recording.bookmarks.sorted { $0.time < $1.time }) { bookmark in
                        Button {
                            player.seek(to: bookmark.time)
                        } label: {
                            HStack {
                                Text(Duration.seconds(bookmark.time), format: .time(pattern: .minuteSecond))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel(SpokenFormat.duration(bookmark.time))
                                Text(bookmark.note ?? "Bookmark")
                            }
                        }
                        .tint(.primary)
                    }
                }
            }
            Section("Status") {
                LabeledContent("Stage", value: recording.stage.displayName)
                if let message = recording.failureMessage {
                    Text(message).foregroundStyle(VFColor.danger)
                }
                if let engine = recording.transcriptionEngine {
                    LabeledContent("Speech engine", value: engineName(engine))
                }
                LabeledContent("Template", value: recording.templateID.displayName)
                if !recording.tags.isEmpty {
                    LabeledContent("Tags", value: recording.tags.joined(separator: ", "))
                }
                LabeledContent("Duration") {
                    Text(Duration.seconds(recording.duration), format: .time(pattern: .minuteSecond))
                }
                if let file = player.fileDescription {
                    LabeledContent("File", value: file)
                }
            }
            if !recording.speakers.isEmpty {
                Section {
                    ForEach(recording.speakers.sorted { $0.key < $1.key }, id: \.key) { speaker in
                        Label {
                            Text(speaker.displayName)
                        } icon: {
                            Image(systemName: "circle.fill")
                                .foregroundStyle(SpeakerPalette.color(for: speaker.colorIndex))
                        }
                    }
                } header: {
                    Text("Speakers")
                } footer: {
                    Text("Labels can be wrong when people talk over each other. Tap a name in the transcript to rename it, or use the Speakers menu to merge two labels.")
                }
            }
        }
    }

    private func engineName(_ engine: TranscriptionEngine) -> String {
        switch engine {
        case .speechTranscriber: "Apple Speech"
        case .dictationTranscriber: "Apple Speech (standard accuracy)"
        case .parakeet: "Parakeet"
        case .fake: "Sample"
        }
    }
}

/// Share sheet, mail composer, and export errors once the controller exists.
private struct OptionalExportPresentation: ViewModifier {
    let controller: ExportController?

    func body(content: Content) -> some View {
        if let controller {
            content.modifier(ExportPresentation(controller: controller))
        } else {
            content
        }
    }
}

/// Applies the shared alerts and sheets once the controller exists.
private struct OptionalRecordingActions: ViewModifier {
    let controller: RecordingActionsController?
    let allTags: [String]

    func body(content: Content) -> some View {
        if let controller {
            content.modifier(RecordingActionsModifier(controller: controller, allTags: allTags))
        } else {
            content
        }
    }
}

#Preview {
    NavigationStack {
        RecordingDetailView(recording: PreviewData.sampleRecording())
    }
    .modelContainer(PreviewData.container())
    .environment(\.services, .fakes())
    .environment(AppState(services: .fakes()))
}
