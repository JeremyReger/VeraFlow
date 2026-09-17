import SwiftUI

public struct RecordingDetailView: View {
    let recording: Recording
    @State private var selectedTab: DetailTab = .summary
    
    public enum DetailTab: String, CaseIterable, Identifiable {
        case summary = "Summary"
        case transcript = "Transcript"
        case audio = "Audio"
        public var id: String { rawValue }
    }
    
    public init(recording: Recording) {
        self.recording = recording
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $selectedTab) {
                ForEach(DetailTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            TabView(selection: $selectedTab) {
                summaryTab.tag(DetailTab.summary)
                transcriptTab.tag(DetailTab.transcript)
                audioTab.tag(DetailTab.audio)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .navigationTitle(recording.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
    
    private var summaryTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Overview")
                        .font(.headline)
                    Text("AI summary generated locally on this iPhone. Actions and key points are extracted below.")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Action Items")
                        .font(.headline)
                    
                    if let summary = recording.summaries.last,
                       let items = try? JSONDecoder().decode([ActionItem].self, from: summary.actionItemsState),
                       !items.isEmpty {
                        ForEach(items) { item in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(item.isCompleted ? .green : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.task)
                                        .font(.subheadline)
                                    HStack {
                                        if !item.owner.isEmpty {
                                            Text(item.owner)
                                                .font(.caption)
                                                .foregroundColor(.blue)
                                        }
                                        if !item.dueText.isEmpty {
                                            Text("• \(item.dueText)")
                                                .font(.caption)
                                                .foregroundColor(.orange)
                                        }
                                        if !item.timestamp.isEmpty {
                                            Text("▶︎ \(item.timestamp)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } else {
                        Text("No action items extracted yet.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
        }
    }
    
    private var transcriptTab: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if recording.segments.isEmpty {
                    Text("No transcript available.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    ForEach(recording.segments) { segment in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(segment.speakerKey ?? "Speaker")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.blue)
                                
                                Text(formatTime(segment.start))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Text(segment.text)
                                .font(.body)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .padding()
        }
    }
    
    private var audioTab: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "waveform")
                .font(.system(size: 72))
                .foregroundColor(.accentColor)
            Text("Audio Player")
                .font(.title2)
                .fontWeight(.medium)
            Text("Duration: \(Int(recording.duration)) seconds")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding()
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

#Preview {
    NavigationStack {
        RecordingDetailView(recording: PreviewData.sampleRecording)
    }
}
