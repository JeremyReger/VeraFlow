import SwiftUI

/// Summary / Transcript / Audio tabs for one recording (SPEC §4.4). Placeholder in M0; built in M3–M5.
struct RecordingDetailView: View {
    let recording: Recording

    var body: some View {
        List {
            Section("Status") {
                LabeledContent("Stage", value: recording.stage.displayName)
                if let message = recording.failureMessage {
                    Text(message).foregroundStyle(.red)
                }
                LabeledContent("Template", value: recording.templateID.displayName)
                LabeledContent("Duration") {
                    Text(Duration.seconds(recording.duration), format: .time(pattern: .minuteSecond))
                }
            }
            if !recording.speakers.isEmpty {
                Section("Speakers") {
                    ForEach(recording.speakers.sorted { $0.key < $1.key }, id: \.key) { speaker in
                        Text(speaker.displayName)
                    }
                }
            }
            if !recording.segments.isEmpty {
                Section("Transcript") {
                    ForEach(recording.orderedSegments, id: \.index) { segment in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(speakerName(for: segment.speakerKey))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(segment.text)
                        }
                    }
                }
            }
        }
        .navigationTitle(recording.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func speakerName(for key: String?) -> String {
        guard let key else { return "Speaker" }
        return recording.speakers.first { $0.key == key }?.displayName ?? key
    }
}

#Preview {
    NavigationStack {
        RecordingDetailView(recording: PreviewData.sampleRecording())
    }
    .modelContainer(PreviewData.container())
}
