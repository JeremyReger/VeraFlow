import SwiftData
import SwiftUI

/// Summary tab (SPEC §4.4): the template output, action items with checkboxes, owner, due date,
/// and a ▶︎ link to the moment it was said. "Change template" re-runs the summary stage; older
/// summaries stay in the history (SPEC §16 M5).
struct SummaryTab: View {
    let recording: Recording
    let player: AudioPlayerController
    @Environment(\.services) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState: AppState?
    @State private var selectedSummaryID: UUID?
    @State private var state = ActionItemsState()
    @State private var showsPaywall = false

    private var summaries: [SummaryRecord] {
        recording.summaries.sorted { $0.createdAt > $1.createdAt }
    }

    private var selected: SummaryRecord? {
        summaries.first { $0.id == selectedSummaryID } ?? summaries.first
    }

    var body: some View {
        VStack(spacing: 0) {
            statusBanner
            if let selected, let payload = try? selected.payload() {
                List {
                    if summaries.count > 1 {
                        historyPicker
                    }
                    content(for: payload, record: selected)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            } else {
                emptyState
            }
        }
        .background(VFColor.background)
        .task(id: selected?.id) {
            state = (try? selected?.actionItems()) ?? ActionItemsState()
        }
        .sheet(isPresented: $showsPaywall) {
            PaywallView()
        }
        // Pipeline stage changes and failures are otherwise silent for VoiceOver (A-4).
        .onChange(of: recording.stage) { _, stage in
            AccessibilityNotification.Announcement(stage.displayName).post()
        }
        .onChange(of: recording.failureMessage) { _, message in
            if let message { AccessibilityNotification.Announcement(message).post() }
        }
    }

    private var isFreeLimitReached: Bool {
        recording.failedStage == .summarizing && recording.failureMessage == SummarizationError.freeLimitMessage
    }

    // MARK: Status

    @ViewBuilder
    private var statusBanner: some View {
        if recording.stage == .summarizing {
            let fraction = appState?.pipelineProgress[recording.id]?.fraction ?? 0
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "sparkles").accessibilityHidden(true)
                    Text("Summarizing…")
                    Spacer()
                    if fraction > 0 {
                        Text(fraction, format: .percent.precision(.fractionLength(0))).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                .font(.footnote)
                ProgressView(value: fraction)
                    .tint(VFColor.accent)
                    .accessibilityLabel("Summarizing")
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(VFColor.surface)
            .accessibilityElement(children: .combine)
        } else if recording.failedStage == .summarizing, let message = recording.failureMessage {
            let unlockedNow = isFreeLimitReached && appState?.isUnlocked == true
            HStack(spacing: 10) {
                Image(systemName: unlockedNow ? "lock.open.fill" : isFreeLimitReached ? "lock.fill" : "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(unlockedNow ? "Unlocked. Tap Retry to write this summary." : message).font(.footnote)
                Spacer(minLength: 0)
                if isFreeLimitReached, appState?.isUnlocked != true {
                    // The natural paywall moment (SPEC §13.3): the fourth summary.
                    Button("Unlock") { showsPaywall = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("summary.unlock")
                } else {
                    Button("Retry") {
                        // Jumps the queue and clears any pending wait.
                        Task { await services.pipeline.prioritize(recordingID: recording.id) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("summary.retry")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(VFColor.surface)
        } else if let appState, !appState.isUnlocked, appState.capabilities?.canSummarize ?? true, recording.summaries.isEmpty {
            Text("\(min(appState.freeSummariesUsed, FreeTier.summaryLimit)) of \(FreeTier.summaryLimit) free summaries used.")
                .vfText(VFText.meta, color: VFColor.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(VFColor.surface)
        }
    }

    private var emptyState: some View {
        Group {
            switch recording.stage {
            case .ready where recording.failedStage != .summarizing:
                VStack(spacing: 14) {
                    Spacer()
                    Image(systemName: "text.document")
                        .font(.system(size: 34))
                        .foregroundStyle(VFColor.textTertiary)
                        .accessibilityHidden(true)
                    Text("No summary yet")
                        .vfText(VFText.cardTitle)
                        .accessibilityAddTraits(.isHeader)
                    Text("Generate one from the transcript with the \(recording.templateID.displayName) template.")
                        .vfText(VFText.body, color: VFColor.textSecondary)
                        .multilineTextAlignment(.center)
                    Button("Summarize") {
                        Task { await services.pipeline.retry(recordingID: recording.id, from: .summarizing) }
                    }
                    .buttonStyle(VFPrimaryPillStyle())
                    .padding(.top, 6)
                    .accessibilityIdentifier("summary.generate")
                    Spacer()
                }
                .padding(.horizontal, VFSpace.gutter + 8)
            case .ready, .summarizing:
                Spacer()
            default:
                ScrollView {
                    ProcessingCard(
                        recording: recording,
                        progress: appState?.pipelineProgress[recording.id],
                        canSummarize: appState?.capabilities?.canSummarize ?? true
                    )
                    .padding(.horizontal, VFSpace.gutterTight)
                    .padding(.vertical, VFSpace.sectionGap)
                }
            }
        }
    }

    // MARK: History

    private var historyPicker: some View {
        Section {
            Picker("Version", selection: Binding(
                get: { selected?.id ?? summaries.first?.id },
                set: { selectedSummaryID = $0 }
            )) {
                ForEach(summaries, id: \.id) { record in
                    Text("\(record.templateID.shortName) · \(record.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())")
                        .tag(Optional(record.id))
                }
            }
        }
    }

    // MARK: Content

    @ViewBuilder
    private func content(for payload: SummaryPayload, record: SummaryRecord) -> some View {
        Section {
            Text(payload.overview)
                .vfText(VFText.summaryBody)
                .padding(.vertical, 4)
                .listRowSeparator(.hidden)
        } header: {
            HStack(spacing: 10) {
                Text(record.templateID.displayName.uppercased())
                    .font(.custom(VFFontName.sansBold, size: 10.5, relativeTo: .caption2))
                    .tracking(1.4)
                    .foregroundStyle(VFColor.accent)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(VFColor.accent.opacity(0.12), in: Capsule())
                    .accessibilityLabel("Template: \(record.templateID.displayName)")
                Spacer()
                templateMenu
            }
            .textCase(nil)
        }

        switch payload {
        case .general(let summary):
            stringList("Key points", summary.keyPoints)
            stringList("Decisions", summary.decisions)
            actionItems(summary.actionItems, record: record)
            stringList("Open questions", summary.openQuestions)
        case .client(let summary):
            stringList("Client goals", summary.clientGoals)
            stringList("Concerns", summary.concerns)
            stringList("Decisions", summary.decisions)
            actionItems(summary.actionItems, record: record)
            if !summary.nextMeeting.isEmpty {
                Section {
                    Text(summary.nextMeeting).vfText(VFText.summaryBody)
                } header: {
                    VFSectionLabel("Next meeting")
                }
            }
            stringList("Open questions", summary.openQuestions)
        case .walkthrough(let summary):
            if !summary.location.isEmpty {
                Section {
                    Text(summary.location).vfText(VFText.summaryBody)
                } header: {
                    VFSectionLabel("Location")
                }
            }
            ForEach(Array(summary.areas.enumerated()), id: \.offset) { _, area in
                workArea(area)
            }
            stringList("Customer requests", summary.customerRequests)
            stringList("Issues found", summary.issuesFound)
            stringList("Quote notes", summary.quoteNotes)
            actionItems(summary.actionItems, record: record)
        }

        Section {
            LabeledContent("Generated", value: record.createdAt.formatted(date: .abbreviated, time: .shortened))
                .vfText(VFText.meta, color: VFColor.textTertiary)
            LabeledContent("Model", value: record.modelInfo)
                .vfText(VFText.meta, color: VFColor.textTertiary)
        } footer: {
            Text("AI-generated from your recording. Check important details.")
                .vfText(VFText.reassurance, color: VFColor.textSecondary)
                .padding(.top, 6)
        }
    }

    private var templateMenu: some View {
        Menu {
            ForEach(TemplateID.allCases) { template in
                Button {
                    rerun(with: template)
                } label: {
                    if template == recording.templateID {
                        Label(template.displayName, systemImage: "checkmark")
                    } else {
                        Text(template.displayName)
                    }
                }
            }
        } label: {
            Text("Change")
                .font(.custom(VFFontName.sansSemiBold, size: 12.5, relativeTo: .caption))
                .foregroundStyle(VFColor.textSecondary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Change template")
        .disabled(recording.stage == .summarizing)
        .accessibilityIdentifier("summary.template")
    }

    /// Sets the template and re-runs only the summary stage; the old summary stays in the history.
    private func rerun(with template: TemplateID) {
        recording.templateID = template
        try? modelContext.save()
        selectedSummaryID = nil
        Task { await services.pipeline.retry(recordingID: recording.id, from: .summarizing) }
    }

    /// Numbered points separated by hairlines (design spec §4 Summary).
    @ViewBuilder
    private func stringList(_ title: String, _ items: [String]) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(index + 1)")
                            .vfText(VFText.meta, color: VFColor.textTertiary)
                            .frame(width: 18, alignment: .trailing)
                            .accessibilityHidden(true)
                        Text(item)
                            .vfText(VFText.summaryBody)
                    }
                    .padding(.vertical, 4)
                    .listRowSeparatorTint(VFColor.separator)
                }
            } header: {
                VFSectionLabel(title)
            }
        }
    }

    @ViewBuilder
    private func workArea(_ area: WorkArea) -> some View {
        Section {
            ForEach(Array(area.tasks.enumerated()), id: \.offset) { _, task in
                Text(task)
            }
            ForEach(Array(area.measurements.enumerated()), id: \.offset) { _, measurement in
                HStack {
                    VStack(alignment: .leading) {
                        Text(measurement.item)
                        Text(measurement.value).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let timestamp = measurement.timestamp {
                        playButton(at: timestamp)
                    }
                }
            }
            ForEach(Array(area.materials.enumerated()), id: \.offset) { _, material in
                VStack(alignment: .leading) {
                    Text(material.name)
                    if !material.quantity.isEmpty || !material.notes.isEmpty {
                        Text([material.quantity, material.notes].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            VFSectionLabel(area.name)
        } footer: {
            if !area.measurements.isEmpty {
                Text("Check measurements against the audio before quoting.")
                    .vfText(VFText.reassurance, color: VFColor.textSecondary)
            }
        }
    }

    // MARK: Action items

    @ViewBuilder
    private func actionItems(_ items: [ActionItem], record: SummaryRecord) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items) { item in
                    actionItemRow(item, record: record)
                        .listRowSeparatorTint(VFColor.separator)
                }
            } header: {
                VFSectionLabel("Action items")
            }
        }
    }

    private func actionItemRow(_ item: ActionItem, record: SummaryRecord) -> some View {
        let done = state.completedItemIDs.contains(item.id)
        return HStack(alignment: .top, spacing: 12) {
            Button {
                toggle(item, in: record)
            } label: {
                Image(systemName: done ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(done ? VFColor.accent : VFColor.textTertiary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(done ? "Mark not done" : "Mark done")

            VStack(alignment: .leading, spacing: 3) {
                Text(item.task)
                    .vfText(VFText.summaryBody, color: done ? VFColor.textTertiary : VFColor.textPrimary)
                    .strikethrough(done)
                HStack(spacing: 8) {
                    if let owner = ownerText(item) {
                        Label(owner, systemImage: "person")
                    }
                    if let dueDate = item.dueDate {
                        Label(dueDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                            .help(item.dueText)
                    } else if !item.dueText.isEmpty {
                        Label(item.dueText, systemImage: "calendar")
                    }
                }
                .vfText(VFText.meta, color: VFColor.textTertiary)
            }
            Spacer(minLength: 0)
            if let timestamp = item.timestamp {
                playButton(at: timestamp)
            }
        }
        .padding(.vertical, 4)
        // One element per action item, with the state spoken and both buttons as actions (A-5).
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "Done" : "Not done")
        .accessibilityActions {
            Button(done ? "Mark not done" : "Mark done") { toggle(item, in: record) }
            if let timestamp = item.timestamp {
                Button("Play from \(SpokenFormat.duration(timestamp))") {
                    player.seek(to: timestamp)
                    player.play()
                }
            }
        }
        .accessibilityIdentifier("summary.actionItem")
    }

    private func ownerText(_ item: ActionItem) -> String? {
        if let key = item.ownerSpeakerKey, let speaker = recording.speakers.first(where: { $0.key == key }) {
            return speaker.displayName
        }
        return item.owner.isEmpty ? nil : item.owner
    }

    private func playButton(at timestamp: TimeInterval) -> some View {
        Button {
            player.seek(to: timestamp)
            player.play()
        } label: {
            Label(TranscriptChunker.timestamp(timestamp), systemImage: "play.circle")
                .font(.caption.monospacedDigit())
                .labelStyle(.titleAndIcon)
                .frame(minHeight: 28)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityLabel("Play from \(SpokenFormat.duration(timestamp))")
    }

    private func toggle(_ item: ActionItem, in record: SummaryRecord) {
        if state.completedItemIDs.contains(item.id) {
            state.completedItemIDs.remove(item.id)
        } else {
            state.completedItemIDs.insert(item.id)
        }
        if let data = try? JSONEncoder().encode(state) {
            record.actionItemsState = data
            try? modelContext.save()
        }
    }
}

#Preview {
    NavigationStack {
        SummaryTab(recording: PreviewData.sampleRecording(), player: AudioPlayerController())
    }
    .modelContainer(PreviewData.container())
    .environment(\.services, .fakes())
    .environment(AppState(services: .fakes()))
}
