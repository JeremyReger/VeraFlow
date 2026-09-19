import SwiftData
import SwiftUI

/// Settings (SPEC §14.2, §14.4, §15): what this iPhone can do, recording defaults, privacy and
/// data controls, About with the hidden Diagnostics screen (7 taps on the version), and DEBUG
/// developer tools. Laid out per the design spec §4 Settings: serif title, Done pill, hairline
/// card groups, italic privacy footer.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.services) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState: AppState?
    @Environment(AppLock.self) private var appLock: AppLock?
    @AppStorage(AppPreferences.appearanceKey) private var appearance: Appearance = .system
    @State private var expectedSpeakers = DiarizationPreference.expectedSpeakers()
    @State private var defaultTemplate = AppPreferences.defaultTemplate()
    @State private var consentReminder = AppPreferences.showsConsentReminder()
    @State private var notifySummaryReady = AppPreferences.notifiesWhenSummaryReady()
    @State private var appLockEnabled = AppPreferences.appLockEnabled()
    @State private var diagnosticsUnlocked = AppPreferences.diagnosticsUnlocked()
    @State private var versionTaps = 0
    @State private var confirmDeleteAll = false
    @State private var deleteMessage: String?
    @Query private var allRecordings: [Recording]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VFSpace.sectionGap) {
                    header
                    deviceGroup
                    displayGroup
                    recordingGroup
                    storageGroup
                    privacyGroup
                    aboutGroup
                    footer
                }
                .padding(.horizontal, VFSpace.gutter)
                .padding(.bottom, VFSpace.bottomInset)
            }
            .background(VFColor.background.ignoresSafeArea())
            // The design draws its own title and Done pill; pushed screens get the bar back.
            .toolbar(.hidden, for: .navigationBar)
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

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center) {
            Text("Settings")
                .vfText(VFText.screenTitle)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button("Done") { dismiss() }
                .font(.custom(VFFontName.sansBold, size: 13.5, relativeTo: .subheadline))
                .foregroundStyle(VFColor.onAccent)
                .padding(.horizontal, 18)
                .frame(minHeight: 38)
                .background(VFColor.accent, in: Capsule())
                .frame(minHeight: VFMetric.minHit)
                .accessibilityIdentifier("settings.done")
        }
        .padding(.top, 18)
    }

    // MARK: This iPhone

    private var deviceGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            VFSectionLabel("This iPhone")
            VFSettingsGroup {
                if let capabilities = appState?.capabilities {
                    statusRow(
                        "Transcription",
                        ok: capabilities.canTranscribe,
                        value: capabilities.transcriptionEngine == .dictationTranscriber ? "Standard accuracy" : capabilities.canTranscribe ? "Ready" : "Not available"
                    )
                    VFHairline()
                    statusRow("AI summaries", ok: capabilities.canSummarize, value: capabilities.canSummarize ? "Ready" : "Not available")
                    VFHairline()
                    statusRow(
                        "Speaker labels",
                        ok: true,
                        value: capabilities.diarizationModelsReady ? "Ready" : "Downloads when first needed"
                    )
                    if !capabilities.canSummarize {
                        Text(OnboardingView.summaryMessage(capabilities.summarization))
                            .vfText(VFText.snippet, color: VFColor.textTertiary)
                            .padding(.bottom, 12)
                    }
                } else {
                    VFSettingsRow(title: "Checking…") { EmptyView() }
                }
            }
        }
    }

    /// Status dot (success or danger) plus the wording, so the state is never colour alone.
    private func statusRow(_ title: String, ok: Bool, value: String) -> some View {
        VFSettingsRow(title: title) {
            HStack(spacing: 8) {
                Circle()
                    .fill(ok ? VFColor.success : VFColor.danger)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(value).vfText(VFText.meta, color: VFColor.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Display

    /// Chalk / Slate by hand, or follow the system (Jeremy's request; the design spec had no picker).
    private var displayGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            VFSectionLabel("Display")
            VFSettingsGroup {
                VFSettingsRow(title: "Appearance", detail: appearance == .system ? "Follows the iPhone setting" : nil) {
                    Menu {
                        ForEach(Appearance.allCases) { choice in
                            Button {
                                appearance = choice
                            } label: {
                                if choice == appearance {
                                    Label(choice.displayName, systemImage: "checkmark")
                                } else {
                                    Text(choice.displayName)
                                }
                            }
                        }
                    } label: {
                        menuValue(appearance.displayName)
                    }
                    .accessibilityLabel("Appearance: \(appearance.displayName)")
                    .accessibilityIdentifier("settings.appearance")
                }
            }
        }
    }

    // MARK: Recording

    private var recordingGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            VFSectionLabel("Recording")
            VFSettingsGroup {
                Toggle("Consent reminder before recording", isOn: $consentReminder)
                    .toggleStyle(VFToggleRowStyle())
                    .onChange(of: consentReminder) { _, value in
                        AppPreferences.setShowsConsentReminder(value)
                    }
                    .accessibilityIdentifier("settings.consentReminder")
                VFHairline()
                Toggle("Notify when a summary is ready", isOn: $notifySummaryReady)
                    .toggleStyle(VFToggleRowStyle(detail: "Only the recording's name is shown"))
                    .onChange(of: notifySummaryReady) { _, value in
                        AppPreferences.setNotifiesWhenSummaryReady(value)
                        if value {
                            Task { _ = await services.notifications.requestAuthorization() }
                        }
                    }
                    .accessibilityIdentifier("settings.notifySummaryReady")
                VFHairline()
                VFSettingsRow(title: "Summary template", detail: "For new recordings") {
                    Menu {
                        ForEach(TemplateID.allCases) { template in
                            Button {
                                defaultTemplate = template
                                AppPreferences.setDefaultTemplate(template)
                            } label: {
                                if template == defaultTemplate {
                                    Label(template.displayName, systemImage: "checkmark")
                                } else {
                                    Text(template.displayName)
                                }
                            }
                        }
                    } label: {
                        menuValue(defaultTemplate.shortName)
                    }
                    .accessibilityLabel("Summary template: \(defaultTemplate.displayName)")
                    .accessibilityIdentifier("settings.template")
                }
                VFHairline()
                NavigationLink {
                    LanguagePickerView()
                } label: {
                    VFSettingsRow(title: "Transcription language", detail: "For new recordings and imports") {
                        HStack(spacing: 6) {
                            Text(transcriptionLanguageName)
                                .vfText(VFText.meta, color: VFColor.textSecondary)
                                .lineLimit(1)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(VFColor.textTertiary)
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Transcription language: \(transcriptionLanguageName)")
                .accessibilityIdentifier("settings.language")
                VFHairline()
                VFSettingsRow(title: "Expected voices", detail: "A hint for speaker labels") {
                    Menu {
                        ForEach(DiarizationPreference.ExpectedSpeakers.allCases, id: \.self) { choice in
                            Button {
                                expectedSpeakers = choice
                                DiarizationPreference.setExpectedSpeakers(choice)
                            } label: {
                                if choice == expectedSpeakers {
                                    Label(choice.displayName, systemImage: "checkmark")
                                } else {
                                    Text(choice.displayName)
                                }
                            }
                        }
                    } label: {
                        menuValue(expectedSpeakers.displayName)
                    }
                    .accessibilityLabel("Expected voices: \(expectedSpeakers.displayName)")
                    .accessibilityIdentifier("settings.expectedSpeakers")
                }
            }
            Text(ConsentSheet.message + " Labels can be wrong when people talk over each other.")
                .vfText(VFText.snippet, color: VFColor.textTertiary)
        }
    }

    private var transcriptionLanguageName: String {
        if let chosen = AppPreferences.transcriptionLocale() {
            return TranscriptionLanguages.name(for: chosen)
        }
        return "iPhone language"
    }

    private func menuValue(_ value: String) -> some View {
        HStack(spacing: 6) {
            Text(value).vfText(VFText.meta, color: VFColor.textSecondary)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(VFColor.textTertiary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: VFMetric.minHit)
        .contentShape(Rectangle())
    }

    // MARK: Storage (v1.1)

    private var trashedCount: Int { allRecordings.filter(\.isTrashed).count }

    private var storageGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            VFSectionLabel("Storage")
            VFSettingsGroup {
                NavigationLink {
                    RecentlyDeletedView()
                } label: {
                    HStack {
                        Text("Recently Deleted").vfText(VFText.rowLabel)
                        Spacer()
                        if trashedCount > 0 {
                            Text("\(trashedCount)").vfText(VFText.meta, color: VFColor.textSecondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(VFColor.textTertiary)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 54)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.recentlyDeleted")
            }
            Text("Deleted recordings can be restored for \(Int(TrashPolicy.retention / 86_400)) days.")
                .vfText(VFText.snippet, color: VFColor.textTertiary)
        }
    }

    // MARK: Privacy

    private var privacyGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            VFSectionLabel("Privacy")
            VFSettingsGroup {
                Toggle("Require Face ID or passcode", isOn: $appLockEnabled)
                    .toggleStyle(VFToggleRowStyle(detail: AppLock.canAuthenticate ? nil : "Set a passcode on this iPhone first"))
                    .disabled(!AppLock.canAuthenticate)
                    .onChange(of: appLockEnabled) { _, value in
                        appLock?.isEnabled = value
                        AppPreferences.setAppLockEnabled(value)
                    }
                    .accessibilityIdentifier("settings.appLock")
                VFHairline()
                Button(role: .destructive) {
                    confirmDeleteAll = true
                } label: {
                    HStack {
                        Text("Delete all data").vfText(VFText.rowLabel, color: VFColor.danger)
                        Spacer()
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(VFColor.danger)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 54)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.deleteAll")
            }
        }
    }

    // MARK: About

    private var aboutGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            VFSectionLabel("About")
            VFSettingsGroup {
                Button {
                    registerVersionTap()
                } label: {
                    VFSettingsRow(title: "Version") {
                        Text(AppInfo.versionString).vfText(VFText.meta, color: VFColor.textSecondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Version \(AppInfo.versionString)")
                .accessibilityIdentifier("settings.version")
                VFHairline()
                VFSettingsRow(title: "Build") {
                    Text(AppInfo.buildName).vfText(VFText.meta, color: VFColor.textSecondary)
                }
                .accessibilityElement(children: .combine)
                VFHairline()
                VFSettingsRow(title: "Speaker models from") {
                    Text(ModelDownload.diarizationModelSourceDescription)
                        .vfText(VFText.meta, color: VFColor.textSecondary)
                        .multilineTextAlignment(.trailing)
                }
                .accessibilityElement(children: .combine)
                if diagnosticsUnlocked {
                    VFHairline()
                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        navigationRow("Diagnostics")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.diagnostics")
                }
                #if DEBUG
                VFHairline()
                NavigationLink {
                    TranscriptionBenchmarkView()
                } label: {
                    navigationRow("Transcription benchmark")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.benchmark")
                #endif
            }
        }
    }

    private func navigationRow(_ title: String) -> some View {
        HStack {
            Text(title).vfText(VFText.rowLabel)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(VFColor.textTertiary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 54)
        .contentShape(Rectangle())
    }

    // MARK: Footer

    private var footer: some View {
        VFReassurance("Everything stays on this iPhone. VeraFlow makes no network requests with your recordings; the only downloads are Apple's speech model, the speaker-label model, and App Store purchases.")
            .padding(.top, 4)
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
