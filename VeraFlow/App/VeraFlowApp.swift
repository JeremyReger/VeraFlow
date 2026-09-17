import SwiftUI
import SwiftData

@main
public struct VeraFlowApp: App {
    let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Recording.self,
            TranscriptSegment.self,
            Speaker.self,
            Bookmark.self,
            SummaryRecord.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    public init() {}

    public var body: some Scene {
        WindowGroup {
            LibraryView()
        }
        .modelContainer(sharedModelContainer)
    }
}
