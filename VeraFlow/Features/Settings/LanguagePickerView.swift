import SwiftUI

/// Settings → Recording → Transcription language (v1.1 plan item 8): the iPhone's language by
/// default, or any locale the speech engine supports on this phone. Picking one that needs
/// assets offers the download right here, with progress.
struct LanguagePickerView: View {
    @Environment(\.services) private var services
    @State private var supported: [Locale] = []
    @State private var chosen = AppPreferences.transcriptionLocale()
    @State private var status: TranscriptionAssetStatus?
    @State private var downloadProgress: Double?
    @State private var errorMessage: String?
    @State private var isLoading = true

    private var effective: Locale { chosen ?? .current }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VFSpace.sectionGap) {
                assetCard
                if isLoading {
                    ProgressView("Checking languages…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
                } else {
                    VFSettingsGroup {
                        let rows = TranscriptionLanguages.options(supported: supported, device: .current, chosen: chosen)
                        ForEach(Array(rows.enumerated()), id: \.element.id) { position, row in
                            if position > 0 { VFHairline() }
                            Button {
                                choose(row.identifier.map { Locale(identifier: $0) })
                            } label: {
                                HStack {
                                    Text(row.name).vfText(VFText.rowLabel)
                                    Spacer()
                                    if row.isSelected {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(VFColor.accent)
                                            .accessibilityHidden(true)
                                    }
                                }
                                .frame(minHeight: 50)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(row.isSelected ? [.isButton, .isSelected] : .isButton)
                            .accessibilityIdentifier("language.\(row.id)")
                        }
                    }
                }
                Text("New recordings and imports are transcribed in this language. A recording can be transcribed again in another language from its menu.")
                    .vfText(VFText.snippet, color: VFColor.textTertiary)
            }
            .padding(.horizontal, VFSpace.gutter)
            .padding(.top, 8)
            .padding(.bottom, VFSpace.bottomInset)
        }
        .background(VFColor.background.ignoresSafeArea())
        .navigationTitle("Transcription language")
        .toolbarTitleDisplayMode(.inline)
        .vfNavigationBar(.visible)
        .task {
            supported = await services.transcription.supportedLocales()
            isLoading = false
            await refreshStatus()
        }
        .alert("Couldn't download", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    /// Whether the picked language's speech model is on the phone, with the one-time download.
    @ViewBuilder
    private var assetCard: some View {
        VFSettingsGroup {
            VFSettingsRow(title: TranscriptionLanguages.name(for: effective), detail: statusText) {
                if let downloadProgress {
                    ProgressView(value: downloadProgress)
                        .frame(width: 90)
                        .accessibilityLabel("Downloading")
                } else if status == .downloadRequired {
                    Button("Download") { Task { await download() } }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier("language.download")
                } else {
                    EmptyView()
                }
            }
        }
    }

    private var statusText: String {
        switch status {
        case .ready: "Speech model installed"
        case .downloadRequired: "Needs a one-time download from Apple"
        case .localeUnsupported: "Not supported on \(Platform.thisDevice)"
        case nil: "Checking…"
        }
    }

    private func choose(_ locale: Locale?) {
        chosen = locale
        AppPreferences.setTranscriptionLocale(locale)
        Task { await refreshStatus() }
    }

    private func refreshStatus() async {
        status = nil
        status = await services.transcription.assetStatus(for: effective)
    }

    private func download() async {
        downloadProgress = 0
        do {
            try await services.transcription.prepareAssets(for: effective) { fraction in
                Task { @MainActor in downloadProgress = fraction }
            }
        } catch {
            errorMessage = PipelineFailure.message(for: error)
        }
        downloadProgress = nil
        await refreshStatus()
    }
}

/// "Transcribe again in…" for one recording (v1.1 plan item 8): pick the language, read what a
/// fresh run replaces, confirm.
struct RetranscribeSheet: View {
    let recording: Recording
    let onConfirm: (Locale) -> Void
    @Environment(\.services) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var supported: [Locale] = []
    @State private var selected: Locale
    @State private var isLoading = true

    init(recording: Recording, onConfirm: @escaping (Locale) -> Void) {
        self.recording = recording
        self.onConfirm = onConfirm
        _selected = State(initialValue: Locale(identifier: recording.localeIdentifier))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if isLoading {
                        ProgressView()
                    } else {
                        Picker("Language", selection: $selected) {
                            ForEach(TranscriptionLanguages.options(supported: supported, device: selected, chosen: selected).dropFirst()) { row in
                                Text(row.name).tag(Locale(identifier: row.identifier ?? ""))
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                } header: {
                    Text("Transcribe again in")
                } footer: {
                    Text("The transcript, speaker labels, and summaries are replaced by a fresh run. Edits to the transcript are lost; marks, tags, and the title stay.")
                }
            }
            .navigationTitle("Transcribe again")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Transcribe") {
                        onConfirm(selected)
                        dismiss()
                    }
                    .disabled(isLoading)
                    .accessibilityIdentifier("retranscribe.confirm")
                }
            }
            .task {
                supported = await services.transcription.supportedLocales()
                isLoading = false
            }
        }
    }
}
