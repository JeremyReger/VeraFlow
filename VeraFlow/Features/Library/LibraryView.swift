import SwiftUI
import SwiftData
import UniformTypeIdentifiers

public struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var recordings: [Recording]
    @AppStorage("consentReminderEnabled") private var consentReminderEnabled = true
    @State private var isConsentSheetPresented = false
    @State private var viewModel = LibraryViewModel()
    @State private var recoveryNotice: String? = nil
    
    private let crashRecoveryService = CrashRecoveryService()
    private let importService: AudioImportServiceProtocol = AudioImportService()
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Interrupted Crash Recovery Banner (§8.2)
                if let notice = recoveryNotice {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                            .foregroundColor(.blue)
                        Text(notice)
                            .font(.caption)
                            .foregroundColor(.primary)
                        Spacer()
                        Button {
                            withAnimation { recoveryNotice = nil }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.blue.opacity(0.12))
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                // Import Success Notice Banner
                if let success = viewModel.importSuccessNotice {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(success)
                            .font(.caption)
                            .foregroundColor(.primary)
                        Spacer()
                        Button {
                            withAnimation { viewModel.importSuccessNotice = nil }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.green.opacity(0.12))
                }
                
                // Import Error Notice Banner
                if let err = viewModel.importErrorMessage {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                        Spacer()
                        Button {
                            withAnimation { viewModel.importErrorMessage = nil }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.12))
                }
                
                // Tag Filter Chip Bar (§16 M2)
                let allTags = viewModel.extractAllTags(from: recordings)
                if !allTags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            TagChip(
                                title: "All",
                                isSelected: viewModel.selectedTag == nil
                            ) {
                                withAnimation { viewModel.selectedTag = nil }
                            }
                            
                            ForEach(allTags, id: \.self) { tag in
                                TagChip(
                                    title: tag,
                                    isSelected: viewModel.selectedTag == tag
                                ) {
                                    withAnimation {
                                        viewModel.selectedTag = (viewModel.selectedTag == tag ? nil : tag)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .background(Color.secondary.opacity(0.04))
                }
                
                // Main Recordings List
                let displayed = viewModel.filterAndSortRecordings(recordings)
                if displayed.isEmpty {
                    ContentUnavailableView(
                        viewModel.searchText.isEmpty ? "No Recordings Yet" : "No Matches Found",
                        systemImage: viewModel.searchText.isEmpty ? "waveform.badge.mic" : "magnifyingglass",
                        description: Text(
                            viewModel.searchText.isEmpty
                            ? "Record in-app or import an audio file using the + menu above."
                            : "Try searching with a different keyword or clearing tag filters."
                        )
                    )
                } else {
                    List {
                        ForEach(displayed) { recording in
                            NavigationLink(destination: RecordingDetailView(recording: recording)) {
                                RecordingRowView(recording: recording)
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    recording.isFavorite.toggle()
                                    try? modelContext.save()
                                } label: {
                                    Label(
                                        recording.isFavorite ? "Unfavorite" : "Favorite",
                                        systemImage: recording.isFavorite ? "star.slash" : "star.fill"
                                    )
                                }
                                .tint(.yellow)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    deleteSingleRecording(recording)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                
                                Button {
                                    viewModel.promptRename(for: recording)
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                            .contextMenu {
                                Button {
                                    viewModel.promptRename(for: recording)
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                
                                Button {
                                    recording.isFavorite.toggle()
                                    try? modelContext.save()
                                } label: {
                                    Label(
                                        recording.isFavorite ? "Remove from Favorites" : "Mark as Favorite",
                                        systemImage: recording.isFavorite ? "star.slash" : "star.fill"
                                    )
                                }
                                
                                Divider()
                                
                                Button(role: .destructive) {
                                    deleteSingleRecording(recording)
                                } label: {
                                    Label("Delete Recording", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(AppConstants.appName)
            .searchable(text: $viewModel.searchText, prompt: "Search titles or tags")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        viewModel.isSettingsPresented = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        // Import Audio File (§16 M2)
                        Button {
                            viewModel.isFileImporterPresented = true
                        } label: {
                            Label("Import Audio File...", systemImage: "square.and.arrow.down")
                        }
                        
                        Divider()
                        
                        // Favorites Toggle
                        Toggle(isOn: $viewModel.showFavoritesOnly) {
                            Label("Favorites Only", systemImage: "star.fill")
                        }
                        
                        Divider()
                        
                        // Sort Options
                        Picker("Sort By", selection: $viewModel.sortOption) {
                            ForEach(LibrarySortOption.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        // Quick Import Button
                        Button {
                            viewModel.isFileImporterPresented = true
                        } label: {
                            Label("Import", systemImage: "square.and.arrow.down")
                                .font(.subheadline)
                        }
                        
                        Spacer()
                        
                        // Record Button (§4.2, §14.2)
                        Button {
                            if consentReminderEnabled {
                                isConsentSheetPresented = true
                            } else {
                                viewModel.isRecordingPresented = true
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "record.circle.fill")
                                    .font(.title3)
                                    .foregroundColor(.red)
                                Text("Record")
                                    .fontWeight(.semibold)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 20)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Capsule())
                        }
                    }
                }
            }
            .sheet(isPresented: $isConsentSheetPresented) {
                ConsentReminderSheet(onConfirm: {
                    viewModel.isRecordingPresented = true
                })
            }
            .sheet(isPresented: $viewModel.isSettingsPresented) {
                SettingsView()
            }
            .sheet(isPresented: $viewModel.isRecordingPresented) {
                RecorderView()
            }
            .fileImporter(
                isPresented: $viewModel.isFileImporterPresented,
                allowedContentTypes: supportedImportUTTypes(),
                allowsMultipleSelection: false
            ) { result in
                handleFileImportResult(result)
            }
            .alert("Rename Recording", isPresented: $viewModel.isRenameAlertPresented) {
                TextField("Title", text: $viewModel.renameTitleText)
                Button("Cancel", role: .cancel) {
                    viewModel.recordingToRename = nil
                }
                Button("Save") {
                    viewModel.applyRename()
                    try? modelContext.save()
                }
            } message: {
                Text("Enter a new title for this recording.")
            }
            .task {
                checkForRecoverableRecordings()
            }
        }
    }
    
    // MARK: - File Import Handling (§16 M2)
    
    private func supportedImportUTTypes() -> [UTType] {
        var types: [UTType] = [.audio, .mpeg4Audio, .mp3, .wav]
        if let caf = UTType("com.apple.coreaudio-format") {
            types.append(caf)
        }
        return types
    }
    
    private func handleFileImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let selectedURL = urls.first else { return }
            importAudioFile(from: selectedURL)
        case .failure(let error):
            withAnimation {
                viewModel.importErrorMessage = "Failed to select file: \(error.localizedDescription)"
            }
        }
    }
    
    public func importAudioFile(from sourceURL: URL) {
        let sessionID = UUID()
        let destinationDir = AppConstants.recordingsDirectoryURL.appendingPathComponent(sessionID.uuidString, isDirectory: true)
        
        Task {
            do {
                let (fileURL, duration, title) = try await importService.importAudio(
                    from: sourceURL,
                    destinationDirectory: destinationDir
                )
                
                await MainActor.run {
                    let recording = Recording(
                        id: sessionID,
                        title: title,
                        createdAt: Date(),
                        duration: duration,
                        audioFileName: fileURL.lastPathComponent,
                        source: .imported,
                        stage: .recorded,
                        tags: ["Imported"]
                    )
                    modelContext.insert(recording)
                    try? modelContext.save()
                    
                    withAnimation {
                        viewModel.importSuccessNotice = "Imported \"\(title)\" (\(formatDuration(duration)))"
                    }
                }
            } catch {
                await MainActor.run {
                    withAnimation {
                        viewModel.importErrorMessage = error.localizedDescription
                    }
                }
            }
        }
    }
    
    // MARK: - Recording Actions
    
    private func checkForRecoverableRecordings() {
        let recovered = crashRecoveryService.scanAndRecover(
            in: modelContext,
            recordingsBaseURL: AppConstants.recordingsDirectoryURL
        )
        if !recovered.isEmpty {
            withAnimation {
                recoveryNotice = "Recovered \(recovered.count) interrupted recording: \(recovered.joined(separator: ", "))"
            }
        }
    }
    
    private func deleteSingleRecording(_ recording: Recording) {
        let fileURL = AppConstants.recordingsDirectoryURL.appendingPathComponent(recording.audioFileName)
        try? FileManager.default.removeItem(at: fileURL)
        modelContext.delete(recording)
        try? modelContext.save()
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// Tag chip button for horizontal category filtering
public struct TagChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color.secondary.opacity(0.12))
                .foregroundColor(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
    }
}

public struct RecordingRowView: View {
    let recording: Recording
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(recording.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(formatDuration(recording.duration))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 8) {
                // Source badge (§7)
                if recording.source == .imported {
                    Text("Imported")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.15))
                        .foregroundColor(.purple)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                
                Text(recording.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Text("•")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Text(recording.stage.displayTitle)
                    .font(.caption2)
                    .foregroundColor(stageColor(recording.stage))
                
                Spacer()
                
                if recording.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundColor(.yellow)
                }
            }
            
            // Tags row
            if !recording.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(recording.tags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 1)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func stageColor(_ stage: PipelineStage) -> Color {
        switch stage {
        case .ready: .green
        case .failed: .red
        case .recording: .red
        default: .blue
        }
    }
}

#Preview {
    LibraryView()
        .modelContainer(for: Recording.self, inMemory: true)
}
