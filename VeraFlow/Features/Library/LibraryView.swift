import SwiftUI
import SwiftData

public struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]
    @State private var viewModel = LibraryViewModel()
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            Group {
                let filtered = viewModel.filterRecordings(recordings)
                if filtered.isEmpty {
                    ContentUnavailableView(
                        "No Recordings Yet",
                        systemImage: "waveform.badge.mic",
                        description: Text("Tap the record button below to start your first on-device transcript.")
                    )
                } else {
                    List {
                        ForEach(filtered) { recording in
                            NavigationLink(destination: RecordingDetailView(recording: recording)) {
                                RecordingRowView(recording: recording)
                            }
                        }
                        .onDelete(perform: deleteRecordings)
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
                
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        viewModel.isRecordingPresented = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "record.circle.fill")
                                .font(.title2)
                                .foregroundColor(.red)
                            Text("Record Meeting")
                                .fontWeight(.semibold)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 20)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                    }
                }
            }
            .sheet(isPresented: $viewModel.isSettingsPresented) {
                SettingsView()
            }
            .sheet(isPresented: $viewModel.isRecordingPresented) {
                RecorderView()
            }
        }
    }
    
    private func deleteRecordings(at offsets: IndexSet) {
        for index in offsets {
            let recording = recordings[index]
            modelContext.delete(recording)
        }
    }
}

public struct RecordingRowView: View {
    let recording: Recording
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
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
