import SwiftUI

/// Three-screen first launch (SPEC §4.1). Placeholder in M0; built in M7.
struct OnboardingView: View {
    var onFinish: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.tint)
            Text("Your meetings, turned into a to-do list.")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("Without the subscription or the cloud.")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Continue", action: onFinish)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding()
    }
}

#Preview {
    OnboardingView(onFinish: {})
}
