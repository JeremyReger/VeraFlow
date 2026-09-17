import SwiftUI

/// Recording screen (SPEC §4.2). Placeholder in M0; built in M1.
struct RecorderView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Recording arrives in M1",
                systemImage: "mic.circle",
                description: Text("Timer, level meter, pause/resume, bookmarks, and crash-safe capture.")
            )
            .navigationTitle("Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    RecorderView()
        .environment(\.services, .fakes())
}
