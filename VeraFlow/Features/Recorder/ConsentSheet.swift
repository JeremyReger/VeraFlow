import SwiftUI

/// Pre-record reminder (SPEC §14.2). Not legal advice; the copy is fixed by the spec.
struct ConsentSheet: View {
    var onContinue: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var dontShowAgain = false

    static let message = "Recording laws vary. Some states require everyone's permission. Let people know you're recording."
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 36

    var body: some View {
        // Scrolls and can grow to the large detent so large text never hides the button (A-16).
        ScrollView {
            VStack(alignment: .leading, spacing: VFSpace.sectionGap) {
                HStack {
                    Text("Before you record")
                        .vfText(VFText.cardTitle)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .vfText(VFText.rowLabel, color: VFColor.accent)
                        .frame(minHeight: VFMetric.minHit)
                        .accessibilityIdentifier("consent.cancel")
                }
                .padding(.top, 18)
                Image(systemName: "person.2.wave.2")
                    .font(.system(size: iconSize, weight: .light))
                    .foregroundStyle(VFColor.accent)
                    .accessibilityHidden(true)
                Text(Self.message)
                    .vfText(VFText.summaryBody)
                VFSettingsGroup {
                    Toggle("Don't show again", isOn: $dontShowAgain)
                        .toggleStyle(VFToggleRowStyle())
                        .accessibilityIdentifier("consent.dontShowAgain")
                }
                Button("Start Recording") {
                    if dontShowAgain {
                        AppPreferences.setShowsConsentReminder(false)
                    }
                    dismiss()
                    onContinue()
                }
                .buttonStyle(VFPrimaryPillStyle())
                .padding(.top, 4)
                .accessibilityIdentifier("consent.continue")
            }
            .padding(.horizontal, VFSpace.gutter)
            .padding(.bottom, VFSpace.bottomInset)
        }
        .background(VFColor.background.ignoresSafeArea())
        .vfSheetDetents([.medium, .large], dragIndicator: true)
        .vfSheetSize(width: 480, height: 560)
    }
}

#Preview {
    ConsentSheet(onContinue: {})
}
