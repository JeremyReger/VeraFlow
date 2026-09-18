import SwiftUI

/// Top-level navigation: onboarding on first launch (SPEC §4.1), the optional app lock
/// (SPEC §14.4), then the Library.
struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @State private var isOnboarded = AppPreferences.onboardingCompleted()
    @State private var lock = AppLock()

    var body: some View {
        Group {
            if isOnboarded {
                NavigationStack {
                    LibraryView()
                }
            } else {
                OnboardingView {
                    AppPreferences.setOnboardingCompleted(true)
                    withAnimation { isOnboarded = true }
                }
            }
        }
        .environment(lock)
        .overlay {
            if lock.isLocked {
                LockScreenView(lock: lock)
                    .transition(.opacity)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                lock.lock()
            case .active:
                Task { await appState.didBecomeActive() }
            default:
                break
            }
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
