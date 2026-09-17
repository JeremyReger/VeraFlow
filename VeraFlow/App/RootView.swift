import SwiftUI

/// Top-level navigation. M0 launches straight into the Library; onboarding gates it from M7.
struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            LibraryView()
        }
        .alert("Interrupted recording", isPresented: Binding(
            get: { appState.recoveryMessage != nil },
            set: { if !$0 { appState.dismissRecoveryMessage() } }
        )) {
            Button("OK") { appState.dismissRecoveryMessage() }
        } message: {
            Text(appState.recoveryMessage ?? "")
        }
    }
}

#Preview {
    RootView()
        .modelContainer(PreviewData.container())
        .environment(\.services, .fakes())
        .environment(AppState(services: .fakes()))
}
