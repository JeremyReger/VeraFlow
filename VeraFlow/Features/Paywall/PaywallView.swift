import SwiftUI

/// One-time unlock screen (SPEC §13.3). Placeholder in M0; built in M8.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Unlock arrives in M8",
                systemImage: "lock.open",
                description: Text("One-time purchase: unlimited summaries, all templates, all exports.")
            )
            .navigationTitle("Unlock VeraFlow")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    PaywallView()
}
