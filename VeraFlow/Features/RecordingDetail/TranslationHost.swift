import SwiftData
import SwiftUI
import Translation

/// Owns the Translation framework session for one recording (v1.1 plan item 14). A
/// `TranslationSession` exists only inside `translationTask`, so this modifier watches the
/// controller's request and runs it there; iOS shows its own pack-download sheet when needed.
///
/// Compiled against the iOS 26.5 SDK on 2026-09-19: `translationTask(_:action:)` and `TranslationSession.Configuration(source:target:)`.
struct TranslationHost: ViewModifier {
    let controller: TranslationController
    let recording: Recording
    @Environment(\.modelContext) private var modelContext
    @State private var configuration: TranslationSession.Configuration?

    func body(content: Content) -> some View {
        content
            .translationTask(configuration) { session in
                await controller.run(recording: recording, context: modelContext, translator: LiveTextTranslator(session: session))
            }
            .onChange(of: controller.requestID) { _, _ in
                guard let language = controller.pendingLanguage else { return }
                let target = Locale.Language(identifier: language)
                if configuration?.target == target {
                    // Same pair as last time: a new value would compare equal and the task
                    // wouldn't run again, so invalidate instead.
                    configuration?.invalidate()
                } else {
                    configuration = TranslationSession.Configuration(
                        source: TranslationLanguages.source(of: recording.localeIdentifier),
                        target: target
                    )
                }
            }
    }
}

/// "Translate to…": the languages this iPhone can translate the recording into, the last
/// choice first. A language that still needs its pack says so; iOS downloads it on first use.
struct TranslationLanguageSheet: View {
    let sourceIdentifier: String
    let onPick: (String) -> Void
    @Environment(\.services) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var languages: [Locale.Language] = []
    @State private var needsDownload: Set<String> = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VFSpace.sectionGap) {
                    if isLoading {
                        ProgressView("Checking languages…")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 20)
                    } else if languages.isEmpty {
                        Text("\(Platform.thisDeviceCapitalized) can't translate \(TranslationLanguages.name(for: sourceIdentifier)) yet.")
                            .vfText(VFText.body, color: VFColor.textSecondary)
                            .padding(.top, 20)
                    } else {
                        VFSettingsGroup {
                            ForEach(Array(languages.enumerated()), id: \.element.minimalIdentifier) { position, language in
                                if position > 0 { VFHairline() }
                                let identifier = language.minimalIdentifier
                                Button {
                                    onPick(identifier)
                                    dismiss()
                                } label: {
                                    HStack {
                                        Text(TranslationLanguages.name(for: language)).vfText(VFText.rowLabel)
                                        Spacer()
                                        if needsDownload.contains(identifier) {
                                            Image(systemName: "arrow.down.circle")
                                                .foregroundStyle(VFColor.textTertiary)
                                                .accessibilityLabel("Downloads a language pack first")
                                        }
                                    }
                                    .frame(minHeight: 50)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("translate.\(identifier)")
                            }
                        }
                    }
                    Text("Translation runs on \(Platform.thisDevice). A language pack is an Apple download, the same as the speech models; nothing from the recording leaves the phone. Names, dates, and measurements are kept as spoken.")
                        .vfText(VFText.snippet, color: VFColor.textTertiary)
                }
                .padding(.horizontal, VFSpace.gutter)
                .padding(.top, 8)
                .padding(.bottom, VFSpace.bottomInset)
            }
            .background(VFColor.background.ignoresSafeArea())
            .navigationTitle("Translate to")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        let source = TranslationLanguages.source(of: sourceIdentifier)
        var targets = await services.translation.targets(from: source)
        if let last = AppPreferences.translationLanguage(),
           let index = targets.firstIndex(where: { $0.minimalIdentifier == last }) {
            targets.insert(targets.remove(at: index), at: 0)
        }
        var pending: Set<String> = []
        for language in targets {
            let status = await services.translation.availability(from: source, to: language)
            if status == .needsDownload { pending.insert(language.minimalIdentifier) }
        }
        languages = targets
        needsDownload = pending
        isLoading = false
    }
}
