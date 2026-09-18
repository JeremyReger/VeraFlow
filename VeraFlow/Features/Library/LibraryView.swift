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
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Settings", systemImage: "gearshape") {
                    isShowingSettings = true
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Menu("More", systemImage: "ellipsis.circle") {
                    Picker("Sort", selection: $filter.sort) {
                        ForEach(LibrarySort.allCases) { sort in
                            Text(sort.displayName).tag(sort)
                        }
                    }
                    Toggle("Favorites Only", systemImage: "star", isOn: $filter.favoritesOnly)
                    Divider()
                    Button("Import from Files", systemImage: "square.and.arrow.down") {
                        isShowingImporter = true
                    }
                    Button("Import Video from Photos", systemImage: "photo.on.rectangle") {
                        isShowingPhotosPicker = true
                    }
                }
                .accessibilityIdentifier("library.more")
                Button("Record", systemImage: "record.circle") {
                    isShowingRecorder = true
                }
            }
        }
        .searchable(text: $filter.searchText, prompt: "Search titles")
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
        .accessibilityIdentifier("library")
    }

    @ViewBuilder
    private func content(_ controller: RecordingActionsController) -> some View {
        if recordings.isEmpty {
            emptyState
        } else {
            List {
                if !allTags.isEmpty {
                    tagChips
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                ForEach(visibleRecordings) { recording in
                    NavigationLink(value: recording.id) {
                        LibraryRow(recording: recording, progress: appState.pipelineProgress[recording.id])
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            controller.requestDelete(recording)
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button(recording.isFavorite ? "Unfavorite" : "Favorite",
                               systemImage: recording.isFavorite ? "star.slash" : "star") {
                            controller.toggleFavorite(recording)
                        }
                        .tint(.yellow)
                    }
                    .contextMenu {
                        RecordingMenuItems(recording: recording, controller: controller)
                    }
                }
            }
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
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var tagChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(allTags, id: \.self) { tag in
                    Button {
                        filter.tag = filter.tag == tag ? nil : tag
                    } label: {
                        Text(tag)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                filter.tag == tag ? Color.accentColor : Color.secondary.opacity(0.15),
                                in: Capsule()
                            )
                            .foregroundStyle(filter.tag == tag ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(filter.tag == tag ? .isSelected : [])
                }
            }
            .padding(.horizontal)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No recordings yet", systemImage: "waveform")
        } description: {
            Text("Tap Record to capture a meeting, or import an audio file. Everything stays on this iPhone.")
        } actions: {
            Button("Record") {
                isShowingRecorder = true
            }
            .buttonStyle(.borderedProminent)
            Button("Import from Files") {
                isShowingImporter = true
            }
            Button("Import Video from Photos") {
                isShowingPhotosPicker = true
            }
        }
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

/// One row in the library list.
struct LibraryRow: View {
    let recording: Recording
    /// Live processing progress from `AppState`, when a stage is running for this recording.
    var progress: PipelineProgress? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(recording.title)
                    .font(.headline)
                    .lineLimit(1)
                if recording.isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .accessibilityLabel("Favorite")
                }
                if recording.source == .imported {
                    Image(systemName: "square.and.arrow.down")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Imported")
                }
            }
            HStack(spacing: 8) {
                Text(recording.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                Text("·")
                Text(Duration.seconds(recording.duration), format: .time(pattern: .minuteSecond))
                if recording.stage != .ready {
                    Text("·")
                    Text(recording.stage.displayName)
                        .foregroundStyle(recording.stage == .failed ? .red : .secondary)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            if !recording.tags.isEmpty {
                Text(recording.tags.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let progress {
                ProgressView(value: progress.fraction)
                    .progressViewStyle(.linear)
                    .tint(progress.isPreparingAssets ? .secondary : .accentColor)
                    .accessibilityLabel(progress.isPreparingAssets ? "Downloading speech model" : progress.stage.displayName)
            }
        }
        .padding(.vertical, 2)
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
