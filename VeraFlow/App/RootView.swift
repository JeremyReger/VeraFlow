import SwiftUI

/// Top-level navigation: onboarding on first launch (SPEC §4.1), the optional app lock
/// (SPEC §14.4), then the Library.
struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @State private var isOnboarded = AppPreferences.onboardingCompleted()
    @State private var lock = AppLock()
    /// Covers the content while the scene is inactive (app switcher, Control Center, an incoming
    /// call) so the snapshot iOS takes never shows a transcript. Only with the app lock on: the
    /// cover is part of that feature (security review S-1).
    @State private var isShielded = false
    /// Settings → Appearance; `nil` scheme follows the system. Applies to the whole scene, sheets included.
    @AppStorage(AppPreferences.appearanceKey) private var appearance: Appearance = .system
    /// Programmatic pushes (a tapped "Summary ready" notification, v1.1 plan item 6).
    @State private var path = NavigationPath()

    var body: some View {
        Group {
            if isOnboarded {
                NavigationStack(path: $path) {
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
        .preferredColorScheme(appearance.colorScheme)
        // Nothing behind the cover is reachable by VoiceOver or Switch Control (A-1).
        .accessibilityHidden(lock.isLocked || isShielded)
        .overlay {
            if lock.isLocked {
                LockScreenView(lock: lock)
                    .transition(.opacity)
            } else if isShielded {
                PrivacyShieldView()
                    .transition(.opacity)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .inactive:
                isShielded = lock.isEnabled
                appState.sceneDidChange(isActive: false)
            case .background:
                isShielded = false
                lock.lock()
                appState.sceneDidChange(isActive: false)
            case .active:
                isShielded = false
                appState.sceneDidChange(isActive: true)
                Task { await appState.didBecomeActive() }
            @unknown default:
                break
            }
        }
        .onChange(of: appState.pendingOpenRecordingID) { _, id in
            guard let id, isOnboarded else { return }
            path = NavigationPath()
            path.append(id)
            appState.clearPendingOpen()
        }
        .onChange(of: lock.isLocked) { _, locked in
            if locked {
                AccessibilityNotification.Announcement("VeraFlow is locked").post()
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
