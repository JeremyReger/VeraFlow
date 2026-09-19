import SwiftData
import SwiftUI

/// Summary / Transcript / Audio tabs for one recording (SPEC §4.4).
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
    /// The transcript's speaker chip (v1.1 plan item 3), kept here so the Audio tab can set it.
    @State private var speakerFilter: String?

    /// Explicit because `@Query` makes the synthesized initializer private. Opens on the Summary
    /// when there is one, otherwise on the Transcript.
    init(recording: Recording) {
        self.recording = recording
        _tab = State(initialValue: recording.currentSummary == nil ? .transcript : .summary)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            switch tab {
            case .summary:
                SummaryTab(recording: recording, player: player)
            case .transcript:
                TranscriptTab(recording: recording, player: player, speakerKey: $speakerFilter)
            case .audio:
                AudioTab(
                    recording: recording,
                    player: player,
                    exportController: exportController,
                    isUnlocked: appState?.isUnlocked ?? false,
                    onLocked: { showsPaywall = true },
                    onSendToReminders: { remindersRecord = recording.currentSummary },
                    onShowSpeaker: { key in
                        speakerFilter = key
                        withAnimation(VFMotion.tabSwitch) { tab = .transcript }
                    }
                )
            }
        }
        .background(VFColor.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if tab != .audio {
                MiniPlayerBar(player: player)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(VFColor.background, for: .navigationBar)
        .toolbar {
            if let controller {
                ToolbarItem(placement: .primaryAction) {
                    Button(recording.isFavorite ? "Unstar" : "Star", systemImage: recording.isFavorite ? "star.fill" : "star") {
                        controller.toggleFavorite(recording)
                    }
                    .accessibilityIdentifier("detail.star")
                }
            }
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
            if recording.audioAvailable {
                player.load(url: services.storage.audioURL(for: recording.id, fileName: recording.audioFileName), title: recording.title)
            } else {
                player.markUnavailable("The audio isn't on this iPhone; it wasn't included when this recording was imported.")
            }
            // Opened: the "Summary ready" notification for it has done its job.
            await services.notifications.clear(recordingID: recording.id)
        }
        .onDisappear { player.stop() }
    }

    /// Serif title, one metadata line, and the underline tabs (design spec §4 Summary / Transcript / Audio).
    private var header: some View {
        let card = LibraryCardModel(recording: recording)
        return VStack(alignment: .leading, spacing: 8) {
            Text(card.title)
                .vfText(VFText.recordingTitle)
                .lineLimit(3)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 7) {
                Text(recording.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                Text("·").accessibilityHidden(true)
                Text(card.duration)
                    .accessibilityLabel(SpokenFormat.duration(recording.duration))
                if card.speakerCount > 0 {
                    Text("·").accessibilityHidden(true)
                    Text("^[\(card.speakerCount) speaker](inflect: true)")
                }
                if card.isImported {
                    Text("·").accessibilityHidden(true)
                    Text("Imported")
                }
            }
            .vfText(VFText.meta, color: VFColor.textTertiary)
            VFTabs(tabs: Tab.allCases.map { (tab: $0, title: $0.title) }, selection: $tab)
                .padding(.top, 6)
                .accessibilityIdentifier("detail.tabs")
        }
        .padding(.horizontal, VFSpace.gutterTight)
        .padding(.top, 4)
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
