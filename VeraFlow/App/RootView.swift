import SwiftData
import SwiftUI

/// Top-level navigation: onboarding on first launch (SPEC §4.1), the optional app lock
/// (SPEC §14.4), then the Library. On the Mac the Library is a sidebar and the selected
/// recording fills the detail column (v1.1 plan item 15).
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
    #if os(macOS)
    /// The sidebar's selected recording.
    @State private var selection: UUID?
    @Query private var recordings: [Recording]
    #endif

    var body: some View {
        Group {
            if isOnboarded {
                library
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
                // The Mac is "inactive" whenever another app is in front; covering the window
                // then would blank it while it sits beside the other one, so only iOS shields.
                isShielded = lock.isEnabled && !Platform.isMac
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
            #if os(macOS)
            selection = id
            #else
            path = NavigationPath()
            path.append(id)
            #endif
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

    #if os(macOS)
    private var library: some View {
        NavigationSplitView {
            LibraryView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 340, ideal: 400, max: 560)
        } detail: {
            if let selection, let recording = recordings.first(where: { $0.id == selection && !$0.isTrashed }) {
                NavigationStack {
                    RecordingDetailView(recording: recording)
                }
                .id(selection)
            } else {
                ContentUnavailableView(
                    "Choose a recording",
                    systemImage: "waveform",
                    description: Text("Or press ⌘N to start a new one, or drop an audio file here to import it.")
                )
                .background(VFColor.background)
            }
        }
        // Files dragged from the Finder import like "Open with" does (sandbox access rides with the drop).
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            for url in files {
                appState.enqueueImport(url)
            }
            return !files.isEmpty
        }
    }
    #else
    private var library: some View {
        NavigationStack(path: $path) {
            LibraryView()
        }
    }
    #endif
}

#Preview {
    RootView()
        .modelContainer(PreviewData.container())
        .environment(\.services, .fakes())
        .environment(AppState(services: .fakes()))
}
