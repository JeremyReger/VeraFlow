import SwiftData
import SwiftUI

/// Hidden Diagnostics screen (SPEC §15): every capability check, model info, storage, recent
/// pipeline events with timings, and the recordings that reported a failure.
struct DiagnosticsView: View {
    @Environment(\.services) private var services
    @Environment(AppState.self) private var appState: AppState?
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]
    @State private var modelInfo = "…"
    @State private var storageBytes: Int64?

    var body: some View {
        List {
            Section("Capabilities") {
                if let c = appState?.capabilities {
                    LabeledContent("iOS", value: c.osVersion)
                    LabeledContent("Speech engine", value: c.transcriptionEngine.map(engineName) ?? "None")
                    LabeledContent("Speech assets", value: assetName(c.transcriptionAssets))
                    LabeledContent("Speaker-label models", value: c.diarizationModelsReady ? "Installed" : "Not downloaded")
                    LabeledContent("AI summaries", value: availabilityName(c.summarization))
                    LabeledContent("Runtime token counts", value: c.hasRuntimeContextSize ? "Yes" : "No (estimating)")
                    LabeledContent("Background processing", value: c.backgroundProcessingSupported ? "Supported" : "Not on this device")
                } else {
                    Text("Checking…").foregroundStyle(.secondary)
                }
                Button("Re-check") {
                    Task { await appState?.refreshCapabilities() }
                }
            }
            Section("Models") {
                LabeledContent("Summary model", value: modelInfo)
                LabeledContent("Prompt version", value: "v\(Prompts.version)")
                LabeledContent("Speaker models from", value: ModelDownload.diarizationModelSourceDescription)
                #if DEBUG
                LabeledContent("Speech engine choice", value: EngineSelectingTranscriptionService.choice().displayName)
                #endif
            }
            Section("Storage") {
                LabeledContent("Recordings", value: "\(recordings.count)")
                LabeledContent("Audio on disk", value: storageBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "…")
                LabeledContent("Free space", value: services.storage.availableCapacity().map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "Unknown")
            }
            let failures = recordings.filter { $0.failureMessage != nil }
            if !failures.isEmpty {
                Section("Reported problems") {
                    ForEach(failures) { recording in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(recording.title).font(.subheadline.weight(.semibold))
                            Text("\(recording.failedStage?.displayName ?? recording.stage.displayName): \(recording.failureMessage ?? "")")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            let timings = PipelineTimeline.timings(from: appState?.recentEvents ?? [])
            if !timings.isEmpty {
                Section("Stage timings (this launch)") {
                    ForEach(timings.reversed()) { timing in
                        timingRow(timing)
                    }
                }
            }
            Section("Recent events (this launch)") {
                let events = appState?.recentEvents ?? []
                if events.isEmpty {
                    Text("Nothing yet.").foregroundStyle(.secondary)
                }
                ForEach(events.suffix(40).reversed()) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(PipelineTimeline.describe(entry.event)).font(.footnote)
                        Text(entry.date, format: .dateTime.hour().minute().second())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            modelInfo = await services.summarization.modelInfo()
            storageBytes = Self.folderSize(at: services.storage.rootDirectory)
        }
    }

    private func timingRow(_ timing: PipelineTimeline.StageTiming) -> some View {
        let label = title(for: timing.recordingID) + " · " + timing.stage.displayName
        let seconds = String(format: "%.1f s", timing.seconds)
        let value = timing.succeeded ? seconds : "failed after " + seconds
        return LabeledContent(label) {
            Text(value).foregroundStyle(timing.succeeded ? Color.secondary : VFColor.danger)
        }
    }

    private func title(for id: UUID) -> String {
        recordings.first { $0.id == id }?.title ?? String(id.uuidString.prefix(8))
    }

    private func engineName(_ engine: TranscriptionEngine) -> String {
        switch engine {
        case .speechTranscriber: "SpeechTranscriber (full quality)"
        case .dictationTranscriber: "DictationTranscriber (standard accuracy)"
        case .parakeet: "Parakeet"
        case .fake: "Fake"
        }
    }

    private func assetName(_ status: TranscriptionAssetStatus) -> String {
        switch status {
        case .ready: "Installed"
        case .downloadRequired: "Download needed"
        case .localeUnsupported: "Locale not supported"
        }
    }

    private func availabilityName(_ availability: SummarizationAvailability) -> String {
        switch availability {
        case .available: "Available"
        case .deviceNotEligible: "Device not eligible"
        case .appleIntelligenceNotEnabled: "Apple Intelligence off"
        case .modelNotReady: "Model not ready"
        case .unknown(let detail): "Unavailable (\(detail))"
        }
    }

    /// Total size of everything under `url`.
    nonisolated static func folderSize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}

#Preview {
    NavigationStack {
        DiagnosticsView()
    }
    .modelContainer(PreviewData.container())
    .environment(\.services, .fakes())
    .environment(AppState(services: .fakes()))
}
