import SwiftData
import SwiftUI

@main
struct VeraFlowApp: App {
    private let container: ModelContainer
    private let services: AppServices
    @State private var appState: AppState

    /// Launch argument used by UI tests: in-memory store and fake services, so no microphone is needed.
    static let useFakeServicesArgument = "--use-fake-services"
    /// With the fake services, also inserts the preview recordings so list features can be driven.
    static let seedSampleDataArgument = "--seed-sample-data"
    /// With the fake services, starts on the onboarding flow instead of skipping it.
    static let showOnboardingArgument = "--show-onboarding"
    /// Live services, but straight to the Library (the launch UI test).
    static let skipOnboardingArgument = "--skip-onboarding"

    init() {
        let useFakes = ProcessInfo.processInfo.arguments.contains(Self.useFakeServicesArgument)
        do {
            if useFakes {
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
            } else {
                container = try ModelContainerFactory.makePersistent()
                services = try AppServices.live(container: container)
                if ProcessInfo.processInfo.arguments.contains(Self.skipOnboardingArgument) {
                    AppPreferences.setOnboardingCompleted(true)
                    AppPreferences.setAppLockEnabled(false)
                }
            }
        } catch {
            // Without a store or file storage the app can't do anything useful.
            fatalError("VeraFlow failed to start: \(error)")
        }
        _appState = State(initialValue: AppState(services: services, modelContext: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.services, services)
                .environment(appState)
                .task { await appState.startup() }
                .onOpenURL { url in
                    appState.enqueueImport(url)
                }
        }
        .modelContainer(container)
    }
}
