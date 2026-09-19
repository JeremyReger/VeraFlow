import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The list of recordings (SPEC §3): search, sort, favorites, tags, rename, delete, and import.
struct LibraryView: View {
    @Environment(\.services) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]

    @State private var controller: RecordingActionsController?
    @State private var filter = LibraryFilter()
    @State private var isShowingRecorder = false
    @State private var isShowingSettings = false
    @State private var isShowingImporter = false
    @State private var isShowingPhotosPicker = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isImporting = false
    @State private var importMessage: String?
    @State private var isSearching = false

    /// Types the Files picker offers (SPEC M2: m4a, mp3, wav, caf) plus mp4/mov video, whose
    /// audio track is extracted (Teams and Zoom recordings).
    static let importTypes: [UTType] = [
        .mpeg4Audio,
        .mp3,
        .wav,
        UTType("com.apple.coreaudio-format") ?? .audio,
        .mpeg4Movie,
        .quickTimeMovie,
    ]

    private var allTags: [String] { LibraryFilter.allTags(in: recordings) }
    private var visibleRecordings: [Recording] { filter.apply(to: recordings) }

    var body: some View {
        Group {
            if let controller {
                content(controller)
                    .modifier(RecordingActionsModifier(controller: controller, allTags: allTags))
            } else {
                Color.clear.task {
                    controller = RecordingActionsController(actions: LibraryActions(context: modelContext, services: services))
                }
            }
        }
        .navigationTitle("Library")
        // The design draws its own header (eyebrow, serif title, round buttons); the system bar
        // stays hidden here and comes back on the pushed detail screen.
        .toolbar(.hidden, for: .navigationBar)
        .background(VFColor.background.ignoresSafeArea())
        .sheet(isPresented: $isShowingRecorder) {
            RecorderView()
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
        .fileImporter(
            isPresented: $isShowingImporter,
            allowedContentTypes: Self.importTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task { await importFiles(urls) }
            case .failure(let error):
                importMessage = error.localizedDescription
            }
        }
        .photosPicker(
            isPresented: $isShowingPhotosPicker,
            selection: $photoItems,
            maxSelectionCount: 10,
            matching: .videos
        )
        .onChange(of: photoItems) { _, items in
            if !items.isEmpty {
                Task { await importPhotoItems(items) }
            }
        }
        .alert("Import", isPresented: Binding(
            get: { importMessage != nil },
            set: { if !$0 { importMessage = nil } }
        )) {
            Button("OK") { importMessage = nil }
        } message: {
            Text(importMessage ?? "")
        }
        .task { await importPendingURLs() }
        .onChange(of: appState.pendingImportURLs) { _, urls in
            if !urls.isEmpty {
                Task { await importPendingURLs() }
            }
        }
        // A real container: without this the identifier would be pushed down onto every child
        // of the VStack and replace the buttons' own identifiers.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library")
    }

    @ViewBuilder
    private func content(_ controller: RecordingActionsController) -> some View {
        if recordings.isEmpty {
            emptyState
        } else {
            // The header and the search field stay put above the list: a text field inside a
            // List row doesn't reliably take focus, and the design keeps the title fixed anyway.
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, VFSpace.gutter)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
                if isSearching {
                    VFField("Search recordings and transcripts", text: $filter.searchText, identifier: "library.search") {
                        if !filter.searchText.isEmpty {
                            Button {
                                filter.searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(VFColor.textTertiary)
                                    .frame(width: 28, height: 28)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel("Clear search")
                        }
                    }
                    .padding(.horizontal, VFSpace.gutter)
                    .padding(.top, 4)
                    .padding(.bottom, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                list(controller)
            }
        }
    }

    private func list(_ controller: RecordingActionsController) -> some View {
        List {
            chips
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 10, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            ForEach(LibraryGrouping.sections(visibleRecordings, sort: filter.sort)) { section in
                Section {
                    ForEach(section.recordings) { recording in
                        LibraryCard(recording: recording, progress: appState.pipelineProgress[recording.id])
                            .overlay {
                                // Hidden link keeps the card free of the list's disclosure chevron.
                                NavigationLink(value: recording.id) { EmptyView() }.opacity(0)
                            }
                            .listRowInsets(EdgeInsets(top: VFSpace.listGap / 2, leading: VFSpace.gutter, bottom: VFSpace.listGap / 2, trailing: VFSpace.gutter))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing) {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    controller.requestDelete(recording)
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button(recording.isFavorite ? "Unstar" : "Star",
                                       systemImage: recording.isFavorite ? "star.slash" : "star") {
                                    controller.toggleFavorite(recording)
                                }
                                .tint(VFColor.accent)
                            }
                            .contextMenu {
                                RecordingMenuItems(recording: recording, controller: controller)
                            }
                    }
                } header: {
                    if !section.title.isEmpty {
                        VFSectionLabel(section.title)
                            .padding(.top, 6)
                    }
                }
            }
            // Room for the pinned Record row.
            Color.clear
                .frame(height: VFMetric.primaryPillHeight + VFSpace.bottomInset)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .navigationDestination(for: UUID.self) { id in
            if let recording = recordings.first(where: { $0.id == id }) {
                RecordingDetailView(recording: recording)
            }
        }
        .overlay {
            if visibleRecordings.isEmpty, filter.isNarrowing {
                ContentUnavailableView.search(text: filter.searchText)
            }
            if isImporting {
                ProgressView("Importing…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: VFRadius.block))
                    .onAppear { AccessibilityNotification.Announcement("Importing").post() }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomActions
        }
    }

    /// Eyebrow, serif title, and the round search / settings / more buttons.
    private var header: some View {
        VFScreenHeader(eyebrow: "VeraFlow", title: "Library") {
            HStack(spacing: 8) {
                VFIconButton(systemName: "magnifyingglass", label: isSearching ? "Hide search" : "Search") {
                    withAnimation(VFMotion.tabSwitch) {
                        isSearching.toggle()
                        if !isSearching { filter.searchText = "" }
                    }
                }
                .accessibilityIdentifier("library.searchButton")
                VFIconButton(systemName: "gearshape", label: "Settings") {
                    isShowingSettings = true
                }
                .accessibilityIdentifier("library.settings")
                Menu {
                    Picker("Sort", selection: $filter.sort) {
                        ForEach(LibrarySort.allCases) { sort in
                            Text(sort.displayName).tag(sort)
                        }
                    }
                    Divider()
                    Button("Import from Files", systemImage: "square.and.arrow.down") {
                        isShowingImporter = true
                    }
                    Button("Import Video from Photos", systemImage: "photo.on.rectangle") {
                        isShowingPhotosPicker = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(VFColor.iconPrimary)
                        .frame(width: VFMetric.iconButton, height: VFMetric.iconButton)
                        .background(VFColor.surface, in: Circle())
                        .overlay { Circle().strokeBorder(VFColor.border, lineWidth: VFMetric.hairline) }
                }
                .accessibilityLabel("More")
                .accessibilityIdentifier("library.more")
            }
        }
    }

    /// All / Starred / the templates in use / the user's tags.
    private var chips: some View {
        let templates = TemplateID.allCases.filter { template in recordings.contains { $0.templateID == template } }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                VFChip("All", isSelected: !filter.favoritesOnly && filter.template == nil && filter.tag == nil) {
                    filter.favoritesOnly = false
                    filter.template = nil
                    filter.tag = nil
                }
                VFChip("Starred", isSelected: filter.favoritesOnly) {
                    filter.favoritesOnly.toggle()
                }
                if templates.count > 1 {
                    ForEach(templates) { template in
                        VFChip(template.shortName, isSelected: filter.template == template) {
                            filter.template = filter.template == template ? nil : template
                        }
                    }
                }
                ForEach(allTags, id: \.self) { tag in
                    VFChip(tag, isSelected: filter.tag == tag) {
                        filter.tag = filter.tag == tag ? nil : tag
                    }
                    .accessibilityHint("Filters the library by this tag")
                }
            }
            .padding(.horizontal, VFSpace.gutter)
        }
    }

    /// The accent Record pill and the round import button over a scrim, so cards scrolling
    /// underneath stay legible (design spec §4 Library).
    private var bottomActions: some View {
        HStack(spacing: 12) {
            Button("Record") {
                isShowingRecorder = true
            }
            .buttonStyle(VFPrimaryPillStyle())
            .accessibilityIdentifier("library.record")
            importMenu {
                VFRoundButtonLabel(systemName: "square.and.arrow.down")
            }
            .accessibilityLabel("Import")
        }
        .padding(.horizontal, VFSpace.gutter)
        .padding(.top, 18)
        .padding(.bottom, 8)
        .background {
            LinearGradient(
                colors: [VFColor.background.opacity(0), VFColor.background, VFColor.background],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    private func importMenu<Content: View>(@ViewBuilder label: () -> Content) -> some View {
        Menu {
            Button("Import from Files", systemImage: "square.and.arrow.down") {
                isShowingImporter = true
            }
            Button("Import Video from Photos", systemImage: "photo.on.rectangle") {
                isShowingPhotosPicker = true
            }
        } label: {
            label()
        }
    }

    /// First run (design spec §4 Library — first run).
    private var emptyState: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, VFSpace.gutter)
                .padding(.top, 8)
            Spacer()
            VStack(spacing: 18) {
                VFWaveformMark(height: 52)
                Text("Your meetings, turned into a to-do list.")
                    .vfText(VFText.recordingTitle)
                    .multilineTextAlignment(.center)
                Text("Record a meeting or import a file. VeraFlow transcribes it, labels who said what, and writes the action items.")
                    .vfText(VFText.body, color: VFColor.textSecondary)
                    .multilineTextAlignment(.center)
                Button("Record") {
                    isShowingRecorder = true
                }
                .buttonStyle(VFPrimaryPillStyle())
                .padding(.top, 8)
                importMenu {
                    Text("Import a file")
                        .vfText(VFText.rowLabel, color: VFColor.accent)
                        .frame(minHeight: VFMetric.minHit)
                }
                .accessibilityLabel("Import a file")
            }
            .padding(.horizontal, 28)
            Spacer()
            VFReassurance()
                .padding(.bottom, VFSpace.bottomInset)
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("library.empty")
    }

    // MARK: Import

    private func importPendingURLs() async {
        let urls = appState.takePendingImports()
        guard !urls.isEmpty else { return }
        await importFiles(urls)
    }

    private func importFiles(_ urls: [URL]) async {
        let actions = LibraryActions(context: modelContext, services: services)
        isImporting = true
        defer { isImporting = false }
        var failures: [String] = []
        for url in urls {
            do {
                try await actions.importAudio(from: url)
            } catch {
                failures.append("\(url.lastPathComponent): \(Self.describe(error))")
            }
        }
        if !failures.isEmpty {
            importMessage = failures.joined(separator: "\n")
        }
    }

    /// Videos from the Photos picker: each is copied to tmp, imported like a dropped mp4/mov,
    /// and the copy removed. The picker runs out of process, so no Photos permission is needed.
    private func importPhotoItems(_ items: [PhotosPickerItem]) async {
        isImporting = true
        var urls: [URL] = []
        var failures: [String] = []
        for item in items {
            do {
                if let video = try await item.loadTransferable(type: PickedVideo.self) {
                    urls.append(video.url)
                } else {
                    failures.append("One selected item isn't a video.")
                }
            } catch {
                failures.append("Couldn't load a video from Photos: \(error.localizedDescription)")
            }
        }
        isImporting = false
        photoItems = []
        await importFiles(urls)
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
        if !failures.isEmpty {
            importMessage = ([importMessage].compactMap { $0 } + failures).joined(separator: "\n")
        }
    }

    private static func describe(_ error: Error) -> String {
        if let error = error as? AudioImportError {
            switch error {
            case .unsupportedType(let ext):
                return "\(ext.isEmpty ? "This file type" : ".\(ext)") isn't supported. Use m4a, mp3, wav, caf, or an mp4/mov video."
            case .unreadable:
                return "The file couldn't be read as audio."
            case .copyFailed(let detail):
                return "Couldn't copy the file: \(detail)"
            }
        }
        return error.localizedDescription
    }
}

/// One card in the library (design spec §4): serif title, two-line gist, then
/// `time · N speakers · N actions`, with the pipeline state while it's still working.
struct LibraryCard: View {
    let recording: Recording
    /// Live processing progress from `AppState`, when a stage is running for this recording.
    var progress: PipelineProgress? = nil

    var body: some View {
        let model = LibraryCardModel(recording: recording)
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(model.title)
                    .vfText(VFText.cardTitle)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if model.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(VFColor.accent)
                        .accessibilityLabel("Starred")
                }
                Text(model.duration)
                    .vfText(VFText.meta, color: VFColor.textTertiary)
                    .accessibilityLabel(SpokenFormat.duration(recording.duration))
            }
            if !model.snippet.isEmpty {
                Text(model.snippet)
                    .vfText(VFText.snippet, color: VFColor.textSecondary)
                    .lineLimit(2)
            }
            HStack(spacing: 7) {
                Text(model.timeOfDay)
                if model.isImported {
                    Text("·").accessibilityHidden(true)
                    Text("Imported")
                }
                if model.isAudioRemoved {
                    Text("·").accessibilityHidden(true)
                    Text("Audio removed")
                }
                if model.speakerCount > 0 {
                    Text("·").accessibilityHidden(true)
                    Text("^[\(model.speakerCount) speaker](inflect: true)")
                }
                if model.actionCount > 0 {
                    Text("·").accessibilityHidden(true)
                    Text("^[\(model.actionCount) action](inflect: true)")
                        .font(.custom(VFFontName.sansSemiBold, size: 11.5, relativeTo: .caption))
                        .foregroundStyle(VFColor.accent)
                }
            }
            .vfText(VFText.meta, color: VFColor.textTertiary)
            .padding(.top, 2)
            if let status = model.status {
                Text(status)
                    .vfText(VFText.meta, color: model.isFailed ? VFColor.danger : VFColor.textSecondary)
                    .lineLimit(2)
            }
            if let progress {
                ProgressView(value: progress.fraction)
                    .progressViewStyle(.linear)
                    .tint(progress.isPreparingAssets ? VFColor.textTertiary : VFColor.accent)
                    .accessibilityLabel(progress.isPreparingAssets ? "Downloading speech model" : progress.stage.displayName)
            }
        }
        .padding(.horizontal, VFSpace.cardPaddingH)
        .padding(.vertical, VFSpace.cardPaddingV)
        .background(VFColor.surface, in: RoundedRectangle(cornerRadius: VFRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: VFRadius.card, style: .continuous)
                .strokeBorder(VFColor.border, lineWidth: VFMetric.hairline)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#Preview("Empty") {
    NavigationStack {
        LibraryView()
    }
    .modelContainer(PreviewData.container(populated: false))
    .environment(\.services, .fakes())
    .environment(AppState(services: .fakes()))
}

#Preview("Populated") {
    NavigationStack {
        LibraryView()
    }
    .modelContainer(PreviewData.container())
    .environment(\.services, .fakes())
    .environment(AppState(services: .fakes()))
}
