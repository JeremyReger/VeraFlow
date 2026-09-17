import SwiftData
import SwiftUI

@main
struct VeraFlowApp: App {
    private let container: ModelContainer
    private let services: AppServices
    @State private var appState: AppState

    init() {
        do {
            container = try ModelContainerFactory.makePersistent()
            services = try AppServices.live()
        } catch {
            // Without a store or file storage the app can't do anything useful.
            fatalError("VeraFlow failed to start: \(error)")
        }
        _appState = State(initialValue: AppState(services: services))
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
