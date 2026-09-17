import SwiftUI

/// Settings (SPEC §14.2, §14.4, §15). M0 shows version and capability info; the rest lands in M7.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState: AppState?
    @State private var expectedSpeakers = DiarizationPreference.expectedSpeakers()

    var body: some View {
        NavigationStack {
            List {
                Section("This iPhone") {
                    if let capabilities = appState?.capabilities {
                        LabeledContent("Transcription", value: capabilities.canTranscribe ? "Available" : "Not available")
                        LabeledContent("AI summaries", value: capabilities.canSummarize ? "Available" : "Not available")
                        LabeledContent("Speaker labels", value: capabilities.diarizationModelsReady ? "Ready" : "Needs download")
                    } else {
                        Text("Checking…").foregroundStyle(.secondary)
                    }
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
                Section("Privacy") {
                    Text("Everything stays on this iPhone. VeraFlow makes no network requests with your recordings.")
                        .font(.footnote)
                }
                Section("About") {
                    LabeledContent("Version", value: AppInfo.versionString)
                    LabeledContent("Build", value: AppInfo.buildName)
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
        .environment(AppState(services: .fakes()))
}
