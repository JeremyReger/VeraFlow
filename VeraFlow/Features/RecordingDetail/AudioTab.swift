import SwiftData
import SwiftUI

/// The Audio tab (design spec §4): waveform scrubber with the playhead, ±15 s transport with a
/// speed pill, per-voice talk time with rename, marks, file details, and the export buttons.
struct AudioTab: View {
    let recording: Recording
    let player: AudioPlayerController
    let exportController: ExportController?
    let isUnlocked: Bool
    let onLocked: () -> Void
    let onSendToReminders: () -> Void

    @Environment(\.services) private var services
    @Environment(\.modelContext) private var modelContext
    @State private var speakerController: SpeakerActionsController?
    @State private var peaks: [CGFloat] = []
    @State private var barCount = 0
    @State private var scrubFraction: Double?
    @ScaledMetric(relativeTo: .title) private var playSize: CGFloat = 64

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VFSpace.sectionGap) {
                playerSection
                if talkTime.count > 1 {
                    talkTimeSection
                }
                if !recording.bookmarks.isEmpty {
                    marksSection
                }
                detailsSection
                exportSection
            }
            .padding(.horizontal, VFSpace.gutterTight)
            .padding(.top, VFSpace.sectionGap)
            .padding(.bottom, VFSpace.bottomInset)
        }
        .background(VFColor.background)
        .modifier(OptionalSpeakerAlerts(controller: speakerController))
        .task {
            if speakerController == nil {
                speakerController = SpeakerActionsController(actions: SpeakerActions(context: modelContext))
            }
        }
        .task(id: barCount) {
            await loadPeaks()
        }
    }

    // MARK: Player

    private var audioURL: URL {
        services.storage.audioURL(for: recording.id, fileName: recording.audioFileName)
    }

    private var progress: Double {
        if let scrubFraction { return scrubFraction }
        guard player.duration > 0 else { return 0 }
        return min(max(player.currentTime / player.duration, 0), 1)
    }

    private var shownTime: TimeInterval {
        scrubFraction.map { $0 * player.duration } ?? player.currentTime
    }

    @ViewBuilder
    private var playerSection: some View {
        if let message = player.errorMessage {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(VFColor.danger).accessibilityHidden(true)
                Text(message).vfText(VFText.snippet, color: VFColor.textSecondary)
            }
            .padding(VFSpace.cardPaddingH)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(VFColor.surface, in: RoundedRectangle(cornerRadius: VFRadius.block, style: .continuous))
        } else {
            VStack(spacing: 14) {
                scrubber
                HStack {
                    Text(timeText(shownTime))
                    Spacer()
                    Text(timeText(player.duration))
                }
                .vfText(VFText.meta, color: VFColor.textTertiary)
                .accessibilityHidden(true)   // the scrubber speaks both times
                transport
            }
            .padding(.horizontal, VFSpace.cardPaddingH)
            .padding(.vertical, VFSpace.cardPaddingV + 4)
            .background(VFColor.surface, in: RoundedRectangle(cornerRadius: VFRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: VFRadius.card, style: .continuous)
                    .strokeBorder(VFColor.border, lineWidth: VFMetric.hairline)
            }
        }
    }

    /// Bars are drawn by `VFWaveform`; this wrapper sizes the bar count to the width, handles
    /// the drag, and carries the VoiceOver semantics (adjustable, ±15 s) the bars don't.
    private var scrubber: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let step = VFMetric.waveformBarWidth + VFMetric.waveformBarGap
            let count = max(8, Int((width + VFMetric.waveformBarGap) / step))
            ZStack(alignment: .leading) {
                VFWaveform(samples: peaks.count == count ? peaks : Array(repeating: 0.08, count: count), progress: progress, height: 72)
                    .frame(width: width, alignment: .leading)
                // Playhead.
                Rectangle()
                    .fill(VFColor.waveformHead)
                    .frame(width: 2, height: 80)
                    .offset(x: max(0, min(width - 2, width * progress)))
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard player.isLoaded, width > 0 else { return }
                        scrubFraction = min(max(value.location.x / width, 0), 1)
                    }
                    .onEnded { value in
                        guard player.isLoaded, width > 0 else { scrubFraction = nil; return }
                        let fraction = min(max(value.location.x / width, 0), 1)
                        player.seek(to: fraction * player.duration)
                        scrubFraction = nil
                    }
            )
            .onAppear { barCount = count }
            .onChange(of: count) { _, newCount in barCount = newCount }
        }
        .frame(height: 80)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(SpokenFormat.duration(shownTime)) of \(SpokenFormat.duration(player.duration))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: player.skip(by: 15)
            case .decrement: player.skip(by: -15)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("audio.scrubber")
    }

    private var transport: some View {
        HStack(spacing: 18) {
            VFIconButton(systemName: "gobackward.15", label: "Back 15 seconds") { player.skip(by: -15) }
                .disabled(!player.isLoaded)
            Spacer(minLength: 0)
            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(VFColor.onAccent)
                    .frame(width: playSize, height: playSize)
                    .background(VFColor.accent, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!player.isLoaded)
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            .accessibilityIdentifier("player.playPause")
            Spacer(minLength: 0)
            VFIconButton(systemName: "goforward.15", label: "Forward 15 seconds") { player.skip(by: 15) }
                .disabled(!player.isLoaded)
            Button {
                player.cycleRate()
            } label: {
                Text(player.rateLabel)
                    .font(.custom(VFFontName.sansBold, size: 12.5, relativeTo: .caption))
                    .foregroundStyle(VFColor.textSecondary)
                    .padding(.horizontal, 12)
                    .frame(height: VFMetric.iconButton)
                    .overlay { Capsule().strokeBorder(VFColor.borderStrong, lineWidth: VFMetric.hairline) }
            }
            .disabled(!player.isLoaded)
            .accessibilityLabel("Playback speed, currently \(player.rateLabel)")
            .accessibilityIdentifier("audio.speed")
        }
    }

    private func loadPeaks() async {
        let count = barCount
        guard count > 0 else { return }
        let url = audioURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let result = await Task.detached(priority: .utility) {
            try? WaveformPeaks.compute(url: url, barCount: count)
        }.value
        if let result, !Task.isCancelled {
            peaks = result
        }
    }

    // MARK: Talk time

    private var talkTime: [TalkTimeShare] {
        TalkTime.shares(segments: recording.segments.map { (speakerKey: $0.speakerKey, start: $0.start, end: $0.end) })
    }

    private var talkTimeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VFSectionLabel("Talk time")
            VFSettingsGroup {
                let shares = talkTime
                ForEach(Array(shares.enumerated()), id: \.element.speakerKey) { position, share in
                    if position > 0 { VFHairline() }
                    talkTimeRow(share)
                }
            }
            Text("Labels can be wrong when people talk over each other. Tap a name to rename it, or use the Speakers menu on the transcript to merge two labels.")
                .vfText(VFText.snippet, color: VFColor.textTertiary)
        }
    }

    @ViewBuilder
    private func talkTimeRow(_ share: TalkTimeShare) -> some View {
        let speaker = recording.speakers.first { $0.key == share.speakerKey }
        let name = speaker?.displayName ?? SpokenFormat.speakerName(forKey: share.speakerKey)
        let colorIndex = speaker?.colorIndex ?? 0
        Button {
            if let speaker { speakerController?.beginRename(speaker) }
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(VFColor.speaker(colorIndex))
                    .frame(width: 9, height: 9)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(name).vfText(VFText.rowLabel)
                        Spacer()
                        Text(timeText(share.seconds))
                            .vfText(VFText.meta, color: VFColor.textSecondary)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(VFColor.surfaceRaised)
                            Capsule().fill(VFColor.speaker(colorIndex))
                                .frame(width: geo.size.width * share.fraction)
                        }
                    }
                    .frame(height: 4)
                    .accessibilityHidden(true)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(VFColor.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 12)
            .frame(minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(speaker == nil)
        .accessibilityLabel("\(name), \(SpokenFormat.duration(share.seconds)), \(Int((share.fraction * 100).rounded())) percent")
        .accessibilityHint(speaker == nil ? "" : "Renames this speaker")
    }

    // MARK: Marks

    private var marksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VFSectionLabel("Marks")
            VFSettingsGroup {
                let marks = recording.bookmarks.sorted { $0.time < $1.time }
                ForEach(Array(marks.enumerated()), id: \.element.persistentModelID) { position, mark in
                    if position > 0 { VFHairline() }
                    Button {
                        player.seek(to: mark.time)
                    } label: {
                        HStack(spacing: 12) {
                            Text(timeText(mark.time))
                                .vfText(VFText.meta, color: VFColor.textSecondary)
                                .accessibilityLabel(SpokenFormat.duration(mark.time))
                            Text(mark.note ?? "Mark").vfText(VFText.rowLabel)
                            Spacer()
                            Image(systemName: "play.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(VFColor.textTertiary)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: 50)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!player.isLoaded)
                    .accessibilityHint("Plays from this moment")
                }
            }
        }
    }

    // MARK: Details

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VFSectionLabel("Details")
            VFSettingsGroup {
                detailRow(recording.source == .imported ? "Imported" : "Recorded",
                          recording.createdAt.formatted(date: .abbreviated, time: .shortened))
                VFHairline()
                detailRow("Length", timeText(recording.duration), spoken: SpokenFormat.duration(recording.duration))
                if let engine = recording.transcriptionEngine {
                    VFHairline()
                    detailRow("Speech engine", Self.engineName(engine))
                }
                VFHairline()
                detailRow("Template", recording.templateID.displayName)
                if !recording.tags.isEmpty {
                    VFHairline()
                    detailRow("Tags", recording.tags.joined(separator: ", "))
                }
                if let file = player.fileDescription {
                    VFHairline()
                    detailRow("File", file)
                }
                VFHairline()
                detailRow("Status", recording.stage.displayName, tint: recording.stage == .failed ? VFColor.danger : nil)
                if let message = recording.failureMessage {
                    Text(message)
                        .vfText(VFText.snippet, color: VFColor.danger)
                        .padding(.bottom, 12)
                }
            }
        }
    }

    private func detailRow(_ title: String, _ value: String, spoken: String? = nil, tint: Color? = nil) -> some View {
        VFSettingsRow(title: title) {
            Text(value)
                .vfText(VFText.meta, color: tint ?? VFColor.textSecondary)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel(spoken ?? value)
        }
        .accessibilityElement(children: .combine)
    }

    static func engineName(_ engine: TranscriptionEngine) -> String {
        switch engine {
        case .speechTranscriber: "Apple Speech"
        case .dictationTranscriber: "Apple Speech (standard accuracy)"
        case .parakeet: "Parakeet"
        case .fake: "Sample"
        }
    }

    // MARK: Exports

    @ViewBuilder
    private var exportSection: some View {
        if let exportController {
            VStack(spacing: VFSpace.listGap) {
                Menu {
                    ExportMenuItems(
                        recording: recording,
                        controller: exportController,
                        onSendToReminders: onSendToReminders,
                        onLocked: onLocked,
                        isUnlocked: isUnlocked
                    )
                } label: {
                    pillLabel("Export transcript", systemName: "square.and.arrow.up")
                }
                .accessibilityIdentifier("audio.exportTranscript")

                Button {
                    if ExportGate.isAllowed(.file(.audio), unlocked: isUnlocked) {
                        let document = ExportDocument.make(from: recording, includeTranscript: false)
                        Task { await exportController.share(.audio, document: document, audioURL: audioURL) }
                    } else {
                        onLocked()
                    }
                } label: {
                    pillLabel("Share audio", systemName: ExportGate.isAllowed(.file(.audio), unlocked: isUnlocked) ? "waveform" : "lock")
                }
                .buttonStyle(.plain)
                .disabled(player.errorMessage != nil)
                .accessibilityHint(ExportGate.isAllowed(.file(.audio), unlocked: isUnlocked) ? "" : "Opens the unlock screen")
                .accessibilityIdentifier("audio.shareAudio")
            }
            .padding(.top, 4)
        }
    }

    private func pillLabel(_ title: String, systemName: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .medium))
                .accessibilityHidden(true)
            Text(title)
        }
        .vfText(VFText.rowLabel, color: VFColor.textPrimary)
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .background(VFColor.surface, in: Capsule())
        .overlay { Capsule().strokeBorder(VFColor.borderStrong, lineWidth: VFMetric.hairline) }
        .contentShape(Capsule())
    }

    private func timeText(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(0, seconds)).formatted(.time(pattern: seconds >= 3_600 ? .hourMinuteSecond : .minuteSecond))
    }
}

#Preview {
    NavigationStack {
        AudioTab(
            recording: PreviewData.sampleRecording(),
            player: AudioPlayerController(),
            exportController: nil,
            isUnlocked: true,
            onLocked: {},
            onSendToReminders: {}
        )
    }
    .modelContainer(PreviewData.container())
    .environment(\.services, .fakes())
}
