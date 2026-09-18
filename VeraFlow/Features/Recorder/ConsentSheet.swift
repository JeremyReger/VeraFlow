import SwiftUI

/// Pre-record reminder (SPEC §14.2). Not legal advice; the copy is fixed by the spec.
struct ConsentSheet: View {
    var onContinue: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var dontShowAgain = false

    static let message = "Recording laws vary. Some states require everyone's permission. Let people know you're recording."
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 40

    var body: some View {
        NavigationStack {
            // Scrolls and can grow to the large detent so large text never hides the button (A-16).
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "person.2.wave.2")
                        .font(.system(size: iconSize))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text(Self.message)
                        .font(.body)
                    Toggle("Don't show again", isOn: $dontShowAgain)
                        .accessibilityIdentifier("consent.dontShowAgain")
                    Button("Start Recording") {
                        if dontShowAgain {
                            AppPreferences.setShowsConsentReminder(false)
                        }
                        dismiss()
                        onContinue()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .accessibilityIdentifier("consent.continue")
                }
                .padding(24)
            }
            .navigationTitle("Before you record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    ConsentSheet(onContinue: {})
}
