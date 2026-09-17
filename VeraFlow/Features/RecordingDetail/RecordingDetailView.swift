import SwiftData
import SwiftUI

/// Summary / Transcript / Audio tabs for one recording (SPEC §4.4). Transcript lands in M3,
/// Summary in M5, the full Audio tab (waveform, speed) in M9.
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
    @Query private var allRecordings: [Recording]
    @State private var tab: Tab
    @State private var player = AudioPlayerController()
    @State private var controller: RecordingActionsController?

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
                summaryTab
            case .transcript:
                TranscriptTab(recording: recording, player: player)
            case .audio:
                audioTab
            }
        }
        .safeAreaInset(edge: .bottom) {
            if tab == .transcript {
                AudioPlayerView(player: player)
                    .padding(.horizontal)
                    .background(.bar)
            }
        }
        .navigationTitle(recording.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
        .task {
            if controller == nil {
                let actions = LibraryActions(context: modelContext, services: services)
                let controller = RecordingActionsController(actions: actions)
                controller.onDeleted = { _ in dismiss() }
                self.controller = controller
            }
            player.load(url: services.storage.audioURL(for: recording.id, fileName: recording.audioFileName))
        }
        .onDisappear { player.stop() }
    }

    private var summaryTab: some View {
        ContentUnavailableView(
            "No summary yet",
            systemImage: "text.document",
            description: Text("Summaries and action items arrive in a later build. The transcript is ready to read now.")
        )
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
                    Text(message).foregroundStyle(.red)
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
                Section("Speakers") {
                    ForEach(recording.speakers.sorted { $0.key < $1.key }, id: \.key) { speaker in
                        Text(speaker.displayName)
                    }
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
