import SwiftData
import SwiftUI

@main
struct VeraFlowApp: App {
    private let container: ModelContainer
    private let services: AppServices
    @State private var appState: AppState

    /// Launch argument used by UI tests: in-memory store and fake services, so no microphone is needed.
    static let useFakeServicesArgument = "--use-fake-services"

    init() {
        let useFakes = ProcessInfo.processInfo.arguments.contains(Self.useFakeServicesArgument)
        do {
            if useFakes {
                container = try ModelContainerFactory.makeInMemory()
                services = .fakes()
            } else {
                container = try ModelContainerFactory.makePersistent()
                services = try AppServices.live()
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
        }
        .modelContainer(container)
    }
}
