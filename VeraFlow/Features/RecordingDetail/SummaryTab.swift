import SwiftData
import SwiftUI

/// Summary tab (SPEC §4.4): the template output, action items with checkboxes, owner, due date,
/// and a ▶︎ link to the moment it was said. "Change template" re-runs the summary stage; older
/// summaries stay in the history (SPEC §16 M5).
struct SummaryTab: View {
    let recording: Recording
    let player: AudioPlayerController
    /// Show the summary's prose in this language when it has been translated (v1.1 plan item 14).
    var translationLanguage: String? = nil
    @Environment(\.services) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState: AppState?
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selectedSummaryID: UUID?
    @State private var state = ActionItemsState()
    @State private var showsPaywall = false
    @Query(sort: \CustomTemplate.createdAt) private var customTemplates: [CustomTemplate]
    /// "Set focus…" from the Change menu (v1.1 plan item 13).
    @State private var focusDraft = ""
    @State private var isEditingFocus = false
    /// The action item being edited or added (v1.1 plan item 2).
    @State private var editing: EditingItem?
    /// The user's corrections to the summary's prose (v1.1 plan item 18).
    @State private var edits = SummaryEdits()
    /// The block whose editor is open.
    @State private var editingSection: SummaryBlock?

    private struct EditingItem: Identifiable {
        var item: ActionItem
        var isNew: Bool
        var id: UUID { item.id }
    }

    private var summaries: [SummaryRecord] {
        recording.summaries.sorted { $0.createdAt > $1.createdAt }
    }

    private var selected: SummaryRecord? {
        summaries.first { $0.id == selectedSummaryID } ?? summaries.first
    }

    /// The translated payload when one is shown, else the model's.
    private func displayedPayload(_ record: SummaryRecord) -> SummaryPayload? {
        if let language = translationLanguage, let translated = record.translation(in: language) {
            return translated
        }
        return try? record.payload()
    }

    private var shownTranslationName: String? {
        guard let language = translationLanguage, let selected, selected.translation(in: language) != nil else { return nil }
        return TranslationLanguages.name(for: language)
    }

    var body: some View {
        VStack(spacing: 0) {
            statusBanner
            if let selected, let payload = displayedPayload(selected) {
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
            edits = (try? selected?.summaryEdits()) ?? SummaryEdits()
        }
        .sheet(isPresented: $showsPaywall) {
            PaywallView()
                .vfSheetSize(width: 520, height: 720)
        }
        .alert("Focus for the summary", isPresented: $isEditingFocus) {
            TextField("e.g. the budget", text: $focusDraft)
            Button("Summarize again") {
                recording.focus = FocusLine.sanitize(focusDraft)
                try? modelContext.save()
                selectedSummaryID = nil
                Task { await services.pipeline.retry(recordingID: recording.id, from: .summarizing) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("One line the summary pays particular attention to. The model still uses only what was said.")
        }
        .sheet(item: $editing) { editing in
            if let record = selected {
                ActionItemEditor(
                    item: editing.item,
                    speakers: recording.speakers,
                    isNew: editing.isNew,
                    onSave: { item in save(item, isNew: editing.isNew, in: record) },
                    onDelete: editing.isNew ? nil : { remove(editing.item.id, in: record) }
                )
            }
        }
        .sheet(item: $editingSection) { block in
            if let record = selected, let payload = try? record.payload() {
                let field = block.field
                let group = block.group
                let modelLines = payload.list(for: field, group: group) ?? []
                let modelParagraph = payload.paragraph(for: field, group: group) ?? ""
                let headingField = block.heading?.field
                let modelHeading = headingField.flatMap { payload.paragraph(for: $0, group: group) }
                SummarySectionEditor(
                    block: block,
                    modelLines: modelLines,
                    modelParagraph: modelParagraph,
                    modelHeading: modelHeading,
                    currentLines: edits.resolved(modelLines, in: field, group: group),
                    currentParagraph: edits.resolved(modelParagraph, in: field, group: group),
                    currentHeading: headingField.map { edits.resolved(modelHeading ?? "", in: $0, group: group) } ?? "",
                    hasEdits: edits.hasEdits(in: field, group: group)
                        || (headingField.map { edits.hasEdits(in: $0, group: group) } ?? false),
                    onSave: { edit in save(edit, in: block, record: record, payload: payload) }
                )
            }
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

    /// The custom template a summary was made with, if it still exists.
    private func customTemplate(for record: SummaryRecord) -> CustomTemplate? {
        guard let id = record.customTemplateID else { return nil }
        return customTemplates.first { $0.id == id }
    }

    @ViewBuilder
    private func content(for payload: SummaryPayload, record: SummaryRecord) -> some View {
        let hidden = customTemplate(for: record)?.hiddenSections ?? []
        let editable = shownTranslationName == nil
        Section {
            Text(edits.resolved(payload.overview, in: .overview))
                .vfText(VFText.summaryBody)
                .padding(.vertical, 4)
                .listRowSeparator(.hidden)
            if edits.hasEdits(in: .overview) {
                editedNote
            }
            if !record.focus.isEmpty {
                Label(record.focus, systemImage: "scope")
                    .vfText(VFText.meta, color: VFColor.textTertiary)
                    .listRowSeparator(.hidden)
                    .accessibilityLabel("Focus: \(record.focus)")
            }
            if let name = shownTranslationName {
                Label("Translated to \(name). Names, dates, and measurements are as spoken.", systemImage: "globe")
                    .vfText(VFText.meta, color: VFColor.textTertiary)
                    .listRowSeparator(.hidden)
                    .accessibilityIdentifier("summary.translated")
            }
        } header: {
            // The controls drop below the template chip once the text is large: side by side the
            // chip truncated to "GEN…" and Change broke as "Chang / e" (Jeremy, 2026-09-20).
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 10))
            layout {
                Text((customTemplate(for: record)?.name ?? record.templateID.displayName).uppercased())
                    .font(.custom(VFFontName.sansBold, size: 10.5, relativeTo: .caption2))
                    .tracking(1.4)
                    .foregroundStyle(VFColor.accent)
                    .padding(.horizontal, 10)
                    // Padding to a minimum, not a fixed height, so the capsule grows with the label.
                    .padding(.vertical, 5)
                    .frame(minHeight: 24)
                    .background(VFColor.accent.opacity(0.12), in: Capsule())
                    .accessibilityLabel("Template: \(record.templateID.displayName)")
                    // Takes the slack in either layout, in place of a `Spacer` that would push the
                    // controls off the bottom of the stacked one.
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 10) {
                    if editable { editButton(for: SummaryBlock(.overview)) }
                    templateMenu
                }
            }
            .textCase(nil)
        }

        let items = payload.resolvedActionItems(applying: state)
        switch payload {
        case .general(let summary):
            // Key points render from the resolved summary: the groups carry the index of the
            // subject they came from, which is where an edit is written back (plan item 18).
            if !hidden.contains(.keyPoints) {
                keyPoints(edits.resolvedTopics(summary.topics), edits.resolved(summary.keyPoints, in: .keyPoints), editable: editable)
            }
            if !hidden.contains(.decisions) { editableList(.decisions, summary.decisions, editable: editable) }
            if !hidden.contains(.actionItems) { actionItems(items, record: record) }
            if !hidden.contains(.openQuestions) { editableList(.openQuestions, summary.openQuestions, editable: editable) }
        case .client(let summary):
            if !hidden.contains(.clientGoals) { editableList(.clientGoals, summary.clientGoals, editable: editable) }
            if !hidden.contains(.concerns) { editableList(.concerns, summary.concerns, editable: editable) }
            if !hidden.contains(.decisions) { editableList(.decisions, summary.decisions, editable: editable) }
            if !hidden.contains(.actionItems) { actionItems(items, record: record) }
            if !hidden.contains(.nextMeeting) { editableParagraph(.nextMeeting, summary.nextMeeting, editable: editable) }
            if !hidden.contains(.openQuestions) { editableList(.openQuestions, summary.openQuestions, editable: editable) }
        case .walkthrough(let summary):
            editableParagraph(.location, summary.location, editable: editable)
            if !hidden.contains(.areas) {
                ForEach(Array(edits.resolvedAreas(summary.areas).enumerated()), id: \.offset) { index, area in
                    workArea(area, at: index, editable: editable)
                }
            }
            if !hidden.contains(.customerRequests) { editableList(.customerRequests, summary.customerRequests, editable: editable) }
            if !hidden.contains(.issuesFound) { editableList(.issuesFound, summary.issuesFound, editable: editable) }
            if !hidden.contains(.quoteNotes) { editableList(.quoteNotes, summary.quoteNotes, editable: editable) }
            if !hidden.contains(.actionItems) { actionItems(items, record: record) }
        }

        addSectionMenu(payload, editable: editable)

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
                    rerun(with: template, custom: nil)
                } label: {
                    if template == recording.templateID, recording.customTemplateID == nil {
                        Label(template.displayName, systemImage: "checkmark")
                    } else {
                        Text(template.displayName)
                    }
                }
            }
            if !customTemplates.isEmpty {
                Divider()
                ForEach(customTemplates, id: \.id) { template in
                    Button {
                        if ExportGate.isAllowed(.customTemplates, unlocked: appState?.isUnlocked ?? false) {
                            rerun(with: template.base, custom: template)
                        } else {
                            showsPaywall = true
                        }
                    } label: {
                        if template.id == recording.customTemplateID {
                            Label(template.name, systemImage: "checkmark")
                        } else {
                            Text(template.name)
                        }
                    }
                }
            }
            Divider()
            Button("Set focus…", systemImage: "scope") {
                focusDraft = recording.focus
                isEditingFocus = true
            }
        } label: {
            Text("Change")
                .font(.custom(VFFontName.sansSemiBold, size: 12.5, relativeTo: .caption))
                .foregroundStyle(VFColor.textSecondary)
                // Its own width, never a share of the row's: without this it was squeezed down to
                // the 44 pt hit area and broke mid-word (Jeremy, 2026-09-20).
                .fixedSize()
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Change template")
        .disabled(recording.stage == .summarizing)
        .accessibilityIdentifier("summary.template")
    }

    /// Sets the template and re-runs only the summary stage; the old summary stays in the history.
    private func rerun(with template: TemplateID, custom: CustomTemplate?) {
        recording.templateID = template
        recording.customTemplateID = custom?.id
        if let custom, recording.focus.isEmpty { recording.focus = custom.focus }
        try? modelContext.save()
        selectedSummaryID = nil
        Task { await services.pipeline.retry(recordingID: recording.id, from: .summarizing) }
    }

    // MARK: Editable sections (v1.1 plan item 18)

    /// The pencil that opens `SummarySectionEditor`. Hidden while a translation is shown: the
    /// edits are in whatever language the user types, so editing translated prose would mix them.
    private func editButton(for block: SummaryBlock, named name: String? = nil) -> some View {
        Button {
            editingSection = block
        } label: {
            Image(systemName: "square.and.pencil")
                .font(.footnote)
                .foregroundStyle(VFColor.accent)
                .frame(minWidth: VFMetric.minHit, minHeight: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit \((name ?? block.field.title).lowercased())")
        .accessibilityIdentifier("summary.editSection")
    }

    private func sectionHeader(_ field: SummaryField, editable: Bool) -> some View {
        HStack(spacing: 8) {
            VFSectionLabel(field.title)
            Spacer(minLength: 0)
            if editable { editButton(for: SummaryBlock(field)) }
        }
        .textCase(nil)
    }

    /// A header for one subject or work area, with the pencil that edits its name and its lines.
    private func groupHeader(_ title: String, block: SummaryBlock, editable: Bool) -> some View {
        HStack(spacing: 8) {
            VFSectionLabel(title)
            Spacer(minLength: 0)
            if editable { editButton(for: block, named: title) }
        }
        .textCase(nil)
    }

    private var editedNote: some View {
        Text("Edited by you. The model's version stays with the summary.")
            .vfText(VFText.meta, color: VFColor.textTertiary)
            .listRowSeparator(.hidden)
    }

    /// Sections this template has that are empty right now. They draw nothing in the body — the
    /// "Add a section" menu at the foot is how the first line gets typed.
    private func emptyFields(in payload: SummaryPayload) -> [SummaryField] {
        payload.editableFields.filter { field in
            if field.isParagraph {
                return edits.resolved(payload.paragraph(for: field) ?? "", in: field).isEmpty
            }
            return edits.resolved(payload.list(for: field) ?? [], in: field).isEmpty
        }
    }

    @ViewBuilder
    private func addSectionMenu(_ payload: SummaryPayload, editable: Bool) -> some View {
        let fields = emptyFields(in: payload)
        if editable, !fields.isEmpty {
            Section {
                Menu {
                    ForEach(fields) { field in
                        Button(field.title) { editingSection = SummaryBlock(field) }
                    }
                } label: {
                    Label("Add a section", systemImage: "plus.circle")
                        .vfText(VFText.rowLabel, color: VFColor.accent)
                        .frame(minHeight: VFMetric.minHit)
                }
                .accessibilityIdentifier("summary.addSection")
            } footer: {
                Text("For something the model left out. It is your text, not the model's.")
                    .vfText(VFText.meta, color: VFColor.textTertiary)
            }
        }
    }

    /// A numbered list the user can rewrite, add to, or clear.
    @ViewBuilder
    private func editableList(_ field: SummaryField, _ modelItems: [String], editable: Bool) -> some View {
        let items = edits.resolved(modelItems, in: field)
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
                sectionHeader(field, editable: editable)
            } footer: {
                if edits.hasEdits(in: field) { editedNote }
            }
        }
    }

    /// One paragraph the user can rewrite (next meeting, location).
    @ViewBuilder
    private func editableParagraph(_ field: SummaryField, _ modelText: String, editable: Bool) -> some View {
        let text = edits.resolved(modelText, in: field)
        if !text.isEmpty {
            Section {
                Text(text).vfText(VFText.summaryBody)
            } header: {
                sectionHeader(field, editable: editable)
            } footer: {
                if edits.hasEdits(in: field) { editedNote }
            }
        }
    }

    /// Stores the editor's result next to the summary; the model's payload is never touched.
    private func save(_ edit: SummarySectionEdit, in block: SummaryBlock, record: SummaryRecord, payload: SummaryPayload) {
        edits.apply(edit, in: block, model: payload)
        do {
            try record.store(edits)
            try modelContext.save()
        } catch {
            AccessibilityNotification.Announcement("Couldn't save the change").post()
        }
    }

    /// One subject → the numbered list; several → each subject as its own section, so the pencil
    /// sits next to the subject it edits (v1.1 plan item 18, tier two). `topics` and `points` are
    /// the user's resolved versions; the group's source says where an edit goes back.
    @ViewBuilder
    private func keyPoints(_ topics: [KeyPointTopic], _ points: [String], editable: Bool) -> some View {
        let groups = KeyPointLayout.groups(topics: topics, keyPoints: points)
        if groups.count == 1, let only = groups.first, only.title == nil {
            editableKeyPointBlock(only, heading: SummaryField.keyPoints.title, editable: editable)
        } else {
            ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                editableKeyPointBlock(
                    group,
                    heading: group.title ?? (index == 0 ? SummaryField.keyPoints.title : "More key points"),
                    editable: editable
                )
            }
        }
    }

    /// One block of key points, with the pencil when the block maps to a single subject.
    @ViewBuilder
    private func editableKeyPointBlock(_ group: KeyPointGroup, heading: String, editable: Bool) -> some View {
        if !group.points.isEmpty {
            Section {
                ForEach(Array(group.points.enumerated()), id: \.offset) { index, point in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(group.title == nil ? "\(index + 1)" : "•")
                            .vfText(VFText.meta, color: VFColor.textTertiary)
                            .frame(width: 18, alignment: .trailing)
                            .accessibilityHidden(true)
                        Text(point)
                            .vfText(VFText.summaryBody)
                    }
                    .padding(.vertical, 4)
                    .listRowSeparatorTint(VFColor.separator)
                }
            } header: {
                switch group.source {
                case .flat:
                    groupHeader(heading, block: SummaryBlock(.keyPoints), editable: editable)
                case .topic(let index):
                    groupHeader(heading, block: SummaryBlock(.topicPoints, group: index), editable: editable)
                case .merged:
                    // Several untitled subjects drawn as one block: no single place to write to.
                    VFSectionLabel(heading)
                }
            } footer: {
                keyPointNote(group.source)
            }
        }
    }

    @ViewBuilder
    private func keyPointNote(_ source: KeyPointSource) -> some View {
        switch source {
        case .flat where edits.hasEdits(in: .keyPoints):
            editedNote
        case .topic(let index) where edits.hasEdits(in: .topicPoints, group: index) || edits.hasEdits(in: .topicTitle, group: index):
            editedNote
        default:
            EmptyView()
        }
    }

    /// One work area. The pencil edits the area's name and its task list; the measurements and
    /// materials underneath are structured, not prose, and stay as the model recorded them.
    @ViewBuilder
    private func workArea(_ area: WorkArea, at index: Int, editable: Bool) -> some View {
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
            groupHeader(area.name, block: SummaryBlock(.areaTasks, group: index), editable: editable)
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if !area.measurements.isEmpty {
                    Text("Check measurements against the audio before quoting.")
                        .vfText(VFText.reassurance, color: VFColor.textSecondary)
                }
                if edits.hasEdits(in: .areaTasks, group: index) || edits.hasEdits(in: .areaName, group: index) {
                    editedNote
                }
            }
        }
    }

    // MARK: Action items

    /// The user's version of the list (edits applied), plus "Add action item" (v1.1 plan item 2).
    @ViewBuilder
    private func actionItems(_ items: [ActionItem], record: SummaryRecord) -> some View {
        Section {
            ForEach(items) { item in
                actionItemRow(item, record: record)
                    .listRowSeparatorTint(VFColor.separator)
            }
            Button {
                editing = EditingItem(item: ActionItem(task: ""), isNew: true)
            } label: {
                Label("Add action item", systemImage: "plus.circle")
                    .vfText(VFText.rowLabel, color: VFColor.accent)
                    .frame(minHeight: VFMetric.minHit)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("summary.addActionItem")
        } header: {
            VFSectionLabel("Action items")
        } footer: {
            if state.hasEdits {
                Text("Edited by you. The original list stays with the summary.")
                    .vfText(VFText.meta, color: VFColor.textTertiary)
            }
        }
    }

    private func save(_ item: ActionItem, isNew: Bool, in record: SummaryRecord) {
        state.save(item, isAdded: isNew)
        persist(in: record)
    }

    private func remove(_ id: UUID, in record: SummaryRecord) {
        state.remove(id)
        persist(in: record)
    }

    private func persist(in record: SummaryRecord) {
        do {
            try record.store(state)
            try modelContext.save()
        } catch {
            AccessibilityNotification.Announcement("Couldn't save the change").post()
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
        .contentShape(Rectangle())
        .onTapGesture {
            editing = EditingItem(item: item, isNew: state.isAdded(item.id))
        }
        // One element per action item, with the state spoken and both buttons as actions (A-5).
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "Done" : "Not done")
        .accessibilityHint("Opens the editor")
        .accessibilityActions {
            Button(done ? "Mark not done" : "Mark done") { toggle(item, in: record) }
            Button("Edit") { editing = EditingItem(item: item, isNew: state.isAdded(item.id)) }
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
