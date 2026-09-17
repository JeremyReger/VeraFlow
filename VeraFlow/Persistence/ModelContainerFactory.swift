import Foundation
import SwiftData

/// Builds the app's SwiftData container.
enum ModelContainerFactory {
    /// Every persisted model type. Add new `@Model` types here.
    static let schema = Schema([
        Recording.self,
        TranscriptSegment.self,
        Speaker.self,
        Bookmark.self,
        SummaryRecord.self,
    ])

    /// The on-disk container used by the app.
    static func makePersistent() throws -> ModelContainer {
        // SwiftData puts its store in Application Support. On a fresh install that folder
        // doesn't exist yet; CoreData recovers by creating it but logs a wall of errors first.
        _ = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// An in-memory container for tests and previews.
    static func makeInMemory() throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
