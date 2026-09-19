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
        CustomTemplate.self,   // v1.1 plan item 13
    ])

    /// The on-disk container used by the app.
    static func makePersistent() throws -> ModelContainer {
        // SwiftData puts its store in Application Support. On a fresh install that folder
        // doesn't exist yet; CoreData recovers by creating it but logs a wall of errors first.
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        // The same path SwiftData picks by default, named explicitly so the files can be
        // protected and kept out of backups like the audio they describe (security review S-6).
        let storeURL = support.appending(path: "default.store")
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        DataProtection.apply(to: DataProtection.storeFiles(for: storeURL))
        let modelCache = support.appending(path: "FluidAudio", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: modelCache, withIntermediateDirectories: true)
        DataProtection.excludeFromBackup(modelCache)
        return container
    }

    /// An in-memory container for tests and previews.
    static func makeInMemory() throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
