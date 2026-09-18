import SwiftData
import SwiftUI

/// Settings (SPEC §14.2, §14.4, §15): recording, speaker labels, privacy and data controls,
/// About with the hidden Diagnostics screen (7 taps on the version), and DEBUG developer tools.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.services) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState: AppState?
    @Environment(AppLock.self) private var appLock: AppLock?
    @State private var expectedSpeakers = DiarizationPreference.expectedSpeakers()
    @State private var consentReminder = AppPreferences.showsConsentReminder()
    @State private var appLockEnabled = AppPreferences.appLockEnabled()
    @State private var diagnosticsUnlocked = AppPreferences.diagnosticsUnlocked()
    @State private var versionTaps = 0
    @State private var confirmDeleteAll = false
    @State private var deleteMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("This iPhone") {
                    if let capabilities = appState?.capabilities {
                        LabeledContent("Transcription", value: capabilities.transcriptionEngine == .dictationTranscriber ? "Standard accuracy" : capabilities.canTranscribe ? "Available" : "Not available")
                        LabeledContent("AI summaries", value: capabilities.canSummarize ? "Available" : "Not available")
                        LabeledContent("Speaker labels", value: capabilities.diarizationModelsReady ? "Ready" : "Downloads when first needed")
                        if !capabilities.canSummarize {
                            Text(OnboardingView.summaryMessage(capabilities.summarization))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Checking…").foregroundStyle(.secondary)
                    }
                }
                Section {
                    Toggle("Consent reminder before recording", isOn: $consentReminder)
                        .onChange(of: consentReminder) { _, value in
                            AppPreferences.setShowsConsentReminder(value)
                        }
                        .accessibilityIdentifier("settings.consentReminder")
                } header: {
                    Text("Recording")
                } footer: {
                    Text(ConsentSheet.message)
                }
                Section {
                    Picker("Expected speakers", selection: $expectedSpeakers) {
                        ForEach(DiarizationPreference.ExpectedSpeakers.allCases, id: \.self) { choice in
                            Text(choice.displayName).tag(choice)
                        }
                    }
                    .onChange(of: expectedSpeakers) { _, choice in
                        DiarizationPreference.setExpectedSpeakers(choice)
                    }
                } header: {
                    Text("Speaker labels")
                } footer: {
                    Text("A hint for the next recording whose speakers are labeled. Labels can be wrong when people talk over each other.")
                }
                Section {
                    Toggle("Require Face ID or passcode", isOn: $appLockEnabled)
                        .disabled(!AppLock.canAuthenticate)
                        .onChange(of: appLockEnabled) { _, value in
                            appLock?.isEnabled = value
                            AppPreferences.setAppLockEnabled(value)
                        }
                        .accessibilityIdentifier("settings.appLock")
                    Button("Delete all data", role: .destructive) {
                        confirmDeleteAll = true
                    }
                    .accessibilityIdentifier("settings.deleteAll")
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Everything stays on this iPhone. VeraFlow makes no network requests with your recordings; the only downloads are Apple's speech model, the speaker-label model, and App Store purchases." + (AppLock.canAuthenticate ? "" : " Set a passcode on this iPhone to use the app lock."))
                }
                Section("About") {
                    LabeledContent("Version", value: AppInfo.versionString)
                        .contentShape(Rectangle())
                        .onTapGesture { registerVersionTap() }
                        .accessibilityIdentifier("settings.version")
                    LabeledContent("Build", value: AppInfo.buildName)
                    LabeledContent("Speaker models from", value: ModelDownload.diarizationModelSourceDescription)
                    if diagnosticsUnlocked {
                        NavigationLink("Diagnostics") {
                            DiagnosticsView()
                        }
                        .accessibilityIdentifier("settings.diagnostics")
                    }
                }
                #if DEBUG
                Section("Developer") {
                    NavigationLink("Transcription benchmark") {
                        TranscriptionBenchmarkView()
                    }
                    .accessibilityIdentifier("settings.benchmark")
                }
                #endif
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Delete all recordings, transcripts, and summaries?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("Delete Everything", role: .destructive) {
                    Task { await deleteAll() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes every recording and its audio from this iPhone. It can't be undone.")
            }
            .alert("Delete all data", isPresented: Binding(get: { deleteMessage != nil }, set: { if !$0 { deleteMessage = nil } })) {
                Button("OK") { deleteMessage = nil }
            } message: {
                Text(deleteMessage ?? "")
            }
        }
    }

    /// Seven taps on the version reveal Diagnostics (SPEC §15); it stays revealed.
    private func registerVersionTap() {
        versionTaps += 1
        if versionTaps >= 7 {
            diagnosticsUnlocked = true
            AppPreferences.setDiagnosticsUnlocked(true)
        }
    }

    private func deleteAll() async {
        do {
            try await LibraryActions(context: modelContext, services: services).deleteAll()
            deleteMessage = "All recordings were deleted."
        } catch {
            deleteMessage = "Couldn't delete everything: \(error.localizedDescription)"
        }
    }
}

/// Bundle facts for the About section and Diagnostics.
enum AppInfo {
    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }

    /// "Riffle (alpha)" for alpha builds, "VeraFlow" otherwise (SPEC §0).
    static var buildName: String {
        #if ALPHA
        return "Riffle (alpha)"
        #else
        return "VeraFlow"
        #endif
    }
}

#Preview {
    SettingsView()
        .modelContainer(PreviewData.container())
        .environment(\.services, .fakes())
        .environment(AppState(services: .fakes()))
        .environment(AppLock(enabled: false))
}
