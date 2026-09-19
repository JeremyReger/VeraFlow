import os
import SwiftData
import SwiftUI

@main
struct VeraFlowApp: App {
    private let container: ModelContainer
    private let services: AppServices
    @State private var appState: AppState
    @State private var commands = AppCommands()

    /// Launch argument used by UI tests: in-memory store and fake services, so no microphone is needed.
    static let useFakeServicesArgument = "--use-fake-services"
    /// With the fake services, also inserts the preview recordings so list features can be driven.
    static let seedSampleDataArgument = "--seed-sample-data"
    /// With the fake services, starts on the onboarding flow instead of skipping it.
    static let showOnboardingArgument = "--show-onboarding"
    /// Live services, but straight to the Library (the launch UI test).
    static let skipOnboardingArgument = "--skip-onboarding"

    init() {
        // Launch arguments exist for UI tests, which run Debug builds. Release binaries ignore
        // them entirely so no argument can swap services or turn the app lock off (security
        // review S-2).
        #if DEBUG
        let useFakes = ProcessInfo.processInfo.arguments.contains(Self.useFakeServicesArgument)
        #else
        let useFakes = false
        #endif
        do {
            if useFakes {
                #if DEBUG
                container = try ModelContainerFactory.makeInMemory()
                services = .fakes()
                // UI tests start on the Library with no consent sheet or lock in the way.
                AppPreferences.setOnboardingCompleted(!ProcessInfo.processInfo.arguments.contains(Self.showOnboardingArgument))
                AppPreferences.setShowsConsentReminder(false)
                AppPreferences.setAppLockEnabled(false)
                if ProcessInfo.processInfo.arguments.contains(Self.seedSampleDataArgument) {
                    for recording in PreviewData.sampleRecordings() {
                        container.mainContext.insert(recording)
                    }
                    try container.mainContext.save()
                }
                #else
                fatalError("Fake services are not built into release builds.")
                #endif
            } else {
                container = try ModelContainerFactory.makePersistent()
                services = try AppServices.live(container: container)
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains(Self.skipOnboardingArgument) {
                    AppPreferences.setOnboardingCompleted(true)
                    AppPreferences.setAppLockEnabled(false)
                }
                #endif
            }
        } catch {
            // Without a store or file storage the app can't do anything useful. The error goes
            // to the log privately; the crash report carries a constant string (S-17).
            Logger(subsystem: "com.jeremyreger.veraflow", category: "startup")
                .fault("startup failed: \(error.localizedDescription, privacy: .private)")
            fatalError("VeraFlow failed to start: the data store could not be opened.")
        }
        _appState = State(initialValue: AppState(services: services, modelContext: container.mainContext))
    }

    var body: some Scene {
        #if os(macOS)
        // One window: a second one would mean a second recorder over the same microphone
        // (v1.1 plan item 15). The menu bar's commands reach the Library through `AppCommands`.
        Window("VeraFlow", id: "main") {
            root
        }
        .defaultSize(width: 1080, height: 720)
        .commands { AppMenuCommands(commands: commands) }
        .modelContainer(container)
        #else
        WindowGroup {
            root
        }
        .modelContainer(container)
        #endif
    }

    private var root: some View {
        RootView()
            .environment(\.services, services)
            .environment(appState)
            .environment(commands)
            .task { await appState.startup() }
            .onOpenURL { url in
                appState.enqueueImport(url)
            }
    }
}
