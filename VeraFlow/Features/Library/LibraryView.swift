import SwiftData
import SwiftUI

/// The list of recordings (SPEC §3). M0 ships the empty state; M2 adds search, tags, and import.
struct LibraryView: View {
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]
    @State private var isShowingRecorder = false
    @State private var isShowingSettings = false

    var body: some View {
        Group {
            if recordings.isEmpty {
                emptyState
            } else {
                List(recordings) { recording in
                    NavigationLink(value: recording.id) {
                        LibraryRow(recording: recording)
                    }
                }
                .navigationDestination(for: UUID.self) { id in
                    if let recording = recordings.first(where: { $0.id == id }) {
                        RecordingDetailView(recording: recording)
                    }
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
            ToolbarItem(placement: .primaryAction) {
                Button("Record", systemImage: "record.circle") {
                    isShowingRecorder = true
                }
            }
        }
        .sheet(isPresented: $isShowingRecorder) {
            RecorderView()
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
        .accessibilityIdentifier("library")
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No recordings yet", systemImage: "waveform")
        } description: {
            Text("Tap Record to capture a meeting. Everything stays on this iPhone.")
        } actions: {
            Button("Record") {
                isShowingRecorder = true
            }
            .buttonStyle(.borderedProminent)
        }
        .accessibilityIdentifier("library.empty")
    }
}

/// One row in the library list.
struct LibraryRow: View {
    let recording: Recording

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
}

#Preview("Populated") {
    NavigationStack {
        LibraryView()
    }
    .modelContainer(PreviewData.container())
    .environment(\.services, .fakes())
}
