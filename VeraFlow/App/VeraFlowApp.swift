import SwiftUI
import SwiftData

@main
public struct VeraFlowApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("faceIDLockEnabled") private var faceIDLockEnabled = false
    
    @State private var isUnlocked = true
    @State private var isOnboardingPresented = false
    
    private let biometricService = BiometricLockService()
    
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
            ZStack {
                LibraryView()
                    .onOpenURL { incomingURL in
                        handleIncomingAudioURL(incomingURL)
                    }
                
                // Biometric Privacy Lock Overlay (§14.4)
                if faceIDLockEnabled && !isUnlocked {
                    biometricLockOverlay
                        .transition(.opacity)
                }
            }
            .fullScreenCover(isPresented: $isOnboardingPresented) {
                OnboardingView()
            }
            .onAppear {
                if !hasCompletedOnboarding {
                    isOnboardingPresented = true
                }
                if faceIDLockEnabled {
                    isUnlocked = false
                    requestBiometricUnlock()
                }
            }
            .onChange(of: hasCompletedOnboarding) { _, completed in
                if completed {
                    isOnboardingPresented = false
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .background:
                    if faceIDLockEnabled {
                        isUnlocked = false
                    }
                case .active:
                    if faceIDLockEnabled && !isUnlocked {
                        requestBiometricUnlock()
                    }
                default:
                    break
                }
            }
        }
        .modelContainer(sharedModelContainer)
    }
    
    // MARK: - Biometric Lock Overlay (§14.4)
    
    private var biometricLockOverlay: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.blue)
                
                VStack(spacing: 8) {
                    Text("\(AppConstants.appName) is Locked")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Unlock to access your private recordings and summaries.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                
                Button {
                    requestBiometricUnlock()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "faceid")
                        Text("Unlock with \(biometricService.biometryType().rawValue)")
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
        }
    }
    
    private func requestBiometricUnlock() {
        Task {
            let success = await biometricService.authenticate()
            await MainActor.run {
                withAnimation {
                    self.isUnlocked = success
                }
            }
        }
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
