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
                .onOpenURL { incomingURL in
                    handleIncomingAudioURL(incomingURL)
                }
        }
        .modelContainer(sharedModelContainer)
    }
    
    // MARK: - Share Sheet / External Audio File Handler (§16 M2)
    
    private func handleIncomingAudioURL(_ url: URL) {
        let importService = AudioImportService()
        guard importService.isSupportedAudioFile(at: url) else { return }
        
        let sessionID = UUID()
        let destinationDir = AppConstants.recordingsDirectoryURL.appendingPathComponent(sessionID.uuidString, isDirectory: true)
        
        Task { @MainActor in
            do {
                let (fileURL, duration, title) = try await importService.importAudio(
                    from: url,
                    destinationDirectory: destinationDir
                )
                let recording = Recording(
                    id: sessionID,
                    title: title,
                    createdAt: Date(),
                    duration: duration,
                    audioFileName: fileURL.lastPathComponent,
                    source: .imported,
                    stage: .recorded,
                    tags: ["Imported"]
                )
                sharedModelContainer.mainContext.insert(recording)
                try? sharedModelContainer.mainContext.save()
            } catch {
                // Ignore unsupported or unreadable file drops
            }
        }
    }
}
