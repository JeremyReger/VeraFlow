import SwiftData
import SwiftUI
import UIKit

/// Recording screen (SPEC §4.2): start, timer, level meter, pause/resume, stop, bookmarks, input
/// and template pickers. Laid out per the design spec §4 (Record — ready / running / paused).
struct RecorderView: View {
    @Environment(\.services) private var services
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: RecorderViewModel?

    var body: some View {
        Group {
            if let viewModel {
                RecorderContent(viewModel: viewModel)
            } else {
                ProgressView()
                    .task {
                        viewModel = RecorderViewModel(services: services, context: modelContext)
                    }
            }
        }
        .background(VFColor.background.ignoresSafeArea())
    }
}

private struct RecorderContent: View {
    @Bindable var viewModel: RecorderViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @ScaledMetric(relativeTo: .largeTitle) private var ringSize: CGFloat = 148
    @ScaledMetric(relativeTo: .largeTitle) private var coreSize: CGFloat = 104
    @ScaledMetric(relativeTo: .title) private var transportSize: CGFloat = 62
    @ScaledMetric(relativeTo: .title) private var stopSize: CGFloat = 84
    @State private var showsConsent = false

    var body: some View {
        Group {
            switch viewModel.phase {
            case .idle:
                readyView
            case .permissionDenied:
                permissionDeniedView
            case .recording, .paused:
                activeView
            case .naming:
                namingView
            case .saved:
                ProgressView()
            }
        }
        .background(VFColor.background.ignoresSafeArea())
        .interactiveDismissDisabled(viewModel.isActive || viewModel.phase == .naming)
        .sheet(isPresented: $showsConsent) {
            ConsentSheet {
                Task { await viewModel.start() }
            }
        }
        .task {
            await viewModel.loadInputs()
            await viewModel.watchInputs()
        }
        .onChange(of: viewModel.phase) { _, phase in
            if case .saved = phase { dismiss() }
            // The status chip changes colour and wording; VoiceOver hears it too (A-4).
            switch phase {
            case .recording: AccessibilityNotification.Announcement("Recording").post()
            case .paused: AccessibilityNotification.Announcement("Paused").post()
            default: break
            }
        }
        .onChange(of: viewModel.notice) { _, notice in
            if let notice { AccessibilityNotification.Announcement(notice).post() }
        }
        .alert("Resume recording?", isPresented: Binding(
            get: { viewModel.isAskingToResume },
            set: { if !$0 { Task { await viewModel.answerResumePrompt(resume: false) } } }
        )) {
            Button("Resume") { Task { await viewModel.answerResumePrompt(resume: true) } }
            Button("Stay paused", role: .cancel) { Task { await viewModel.answerResumePrompt(resume: false) } }
        } message: {
            Text("The interruption ended. Recording is paused.")
        }
        .alert("Recording problem", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.dismissError() } }
        )) {
            Button("OK") { viewModel.dismissError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: Header

    /// Close on the left while nothing is recording; the status chip in the middle once it is.
    @ViewBuilder
    private func headerRow(showsClose: Bool) -> some View {
        ZStack {
            if viewModel.isActive {
                VFLiveChip(viewModel.phase == .paused ? "PAUSED" : "RECORDING", isLive: viewModel.phase == .recording)
                    .accessibilityIdentifier("recorder.status")
            } else {
                Text("New recording".uppercased())
                    .vfText(VFText.sectionLabel, color: VFColor.textTertiary)
                    .accessibilityAddTraits(.isHeader)
            }
            if showsClose {
                HStack {
                    VFIconButton(systemName: "xmark", label: "Close") { dismiss() }
                        .accessibilityIdentifier("recorder.close")
                    Spacer()
                }
            }
        }
        .padding(.horizontal, VFSpace.gutterTight)
        .padding(.top, 12)
    }

    // MARK: Idle

    private var readyView: some View {
        VStack(spacing: 0) {
            headerRow(showsClose: true)
            Spacer()
            Button {
                // Consent reminder first (SPEC §14.2) unless the user turned it off.
                if AppPreferences.showsConsentReminder() {
                    showsConsent = true
                } else {
                    Task { await viewModel.start() }
                }
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(VFColor.borderStrong, lineWidth: 1.5)
                        .frame(width: ringSize, height: ringSize)
                    Circle()
                        .fill(VFColor.accent)
                        .frame(width: coreSize, height: coreSize)
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start Recording")
            .accessibilityIdentifier("recorder.start")
            Text("Tap to start")
                .vfText(VFText.meta, color: VFColor.textTertiary)
                .padding(.top, 18)
                .accessibilityHidden(true)
            Spacer()
            VStack(spacing: VFSpace.listGap) {
                MicrophoneMenu(viewModel: viewModel, compact: false)
                TemplateMenu(viewModel: viewModel)
            }
            .padding(.horizontal, VFSpace.gutter)
            VFReassurance()
                .padding(.top, VFSpace.sectionGap)
                .padding(.bottom, VFSpace.bottomInset)
        }
    }

    // MARK: Permission denied

    private var permissionDeniedView: some View {
        VStack(spacing: 0) {
            headerRow(showsClose: true)
            Spacer()
            VStack(spacing: 14) {
                Image(systemName: "mic.slash")
                    .font(.system(size: 40, weight: .regular))
                    .foregroundStyle(VFColor.textTertiary)
                    .accessibilityHidden(true)
                Text("Microphone access is off")
                    .vfText(VFText.cardTitle)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("VeraFlow needs the microphone to record. Audio never leaves this iPhone.")
                    .vfText(VFText.body, color: VFColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, VFSpace.gutter + 8)
            Spacer()
            VStack(spacing: VFSpace.listGap) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .buttonStyle(VFPrimaryPillStyle())
                Button("Try Again") { Task { await viewModel.start() } }
                    .buttonStyle(VFSecondaryPillStyle())
            }
            .padding(.horizontal, VFSpace.gutter)
            .padding(.bottom, VFSpace.bottomInset)
        }
    }

    // MARK: Recording / paused

    private var isPaused: Bool { viewModel.phase == .paused }

    private var activeView: some View {
        VStack(spacing: 0) {
            headerRow(showsClose: false)

            if let bytes = viewModel.lowDiskBytes {
                LowDiskBanner(availableBytes: bytes)
                    .padding(.horizontal, VFSpace.gutter)
                    .padding(.top, 14)
            }

            Spacer()

            // Dimmed while paused (spec §5), never hidden.
            Text(Duration.seconds(viewModel.snapshot.elapsed), format: .time(pattern: .hourMinuteSecond))
                .vfText(VFText.timerDisplay, color: isPaused ? VFColor.textTertiary : VFColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .accessibilityLabel("Elapsed time")
                .accessibilityValue(SpokenFormat.duration(viewModel.snapshot.elapsed))
                .accessibilityAddTraits(.updatesFrequently)
                .accessibilityIdentifier("recorder.timer")

            WaveformView(samples: viewModel.levelHistory, capacity: RecorderViewModel.waveformSampleCount)
                .frame(height: 84)
                .padding(.horizontal, VFSpace.gutter)
                .padding(.top, 20)
                .opacity(isPaused ? 0.55 : 1)

            LevelMeter(level: viewModel.snapshot.level)
                .frame(height: 4)
                .padding(.horizontal, VFSpace.gutter * 2.5)
                .padding(.top, 16)

            HStack(spacing: 7) {
                if viewModel.bookmarkCount > 0 {
                    Text("^[\(viewModel.bookmarkCount) mark](inflect: true)")
                }
                if let notice = viewModel.notice {
                    if viewModel.bookmarkCount > 0 { Text("·").accessibilityHidden(true) }
                    Text(notice).multilineTextAlignment(.center)
                }
            }
            .vfText(VFText.meta, color: VFColor.textTertiary)
            .padding(.horizontal, VFSpace.gutter)
            .padding(.top, 14)

            MicrophoneMenu(viewModel: viewModel, compact: true)
                .padding(.top, 14)

            Spacer()

            MarkLabelChips(viewModel: viewModel)
                .padding(.bottom, 14)

            transport
                .padding(.bottom, VFSpace.bottomInset)
        }
    }

    /// MARK (62 pt) · stop (84 pt, accent) · PAUSE / RESUME (62 pt), spec §4 Record — running.
    private var transport: some View {
        HStack(spacing: 28) {
            TransportButton(title: "Mark", diameter: transportSize) {
                Task { await viewModel.mark() }
            }
            .accessibilityLabel("Add Bookmark")
            .accessibilityHint("Flags this moment in the recording")
            .accessibilityIdentifier("recorder.bookmark")

            Button {
                Task { await viewModel.stop() }
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(VFColor.onAccent)
                    .frame(width: stopSize, height: stopSize)
                    .background(VFColor.accent, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop")
            .accessibilityIdentifier("recorder.stop")

            if isPaused {
                TransportButton(title: "Resume", diameter: transportSize) {
                    Task { await viewModel.resume() }
                }
                .accessibilityLabel("Resume")
                .accessibilityIdentifier("recorder.resume")
            } else {
                TransportButton(title: "Pause", diameter: transportSize) {
                    Task { await viewModel.pause() }
                }
                .accessibilityLabel("Pause")
                .accessibilityIdentifier("recorder.pause")
            }
        }
    }

    // MARK: Naming

    private var namingView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VFSpace.sectionGap) {
                Text("Name this recording")
                    .vfText(VFText.screenTitle)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 24)

                VStack(alignment: .leading, spacing: 8) {
                    VFSectionLabel("Title")
                    TextField("Title", text: $viewModel.draftTitle)
                        .vfText(VFText.rowLabel)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 50)
                        .background(VFColor.surface, in: RoundedRectangle(cornerRadius: VFRadius.field, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: VFRadius.field, style: .continuous)
                                .strokeBorder(VFColor.border, lineWidth: VFMetric.hairline)
                        }
                        .accessibilityIdentifier("recorder.title")
                }

                VFSettingsGroup {
                    VFSettingsRow(title: "Length") {
                        Text(Duration.seconds(viewModel.recording?.duration ?? 0), format: .time(pattern: .hourMinuteSecond))
                            .vfText(VFText.meta, color: VFColor.textSecondary)
                            .accessibilityLabel(SpokenFormat.duration(viewModel.recording?.duration ?? 0))
                    }
                    VFHairline()
                    VFSettingsRow(title: "Summary template") {
                        Text(viewModel.selectedTemplate.shortName)
                            .vfText(VFText.meta, color: VFColor.textSecondary)
                    }
                    if viewModel.bookmarkCount > 0 {
                        VFHairline()
                        VFSettingsRow(title: "Marks") {
                            Text("\(viewModel.bookmarkCount)")
                                .vfText(VFText.meta, color: VFColor.textSecondary)
                        }
                    }
                }

                Button("Save") { Task { await viewModel.save() } }
                    .buttonStyle(VFPrimaryPillStyle())
                    .accessibilityIdentifier("recorder.save")
                    .padding(.top, 6)
            }
            .padding(.horizontal, VFSpace.gutter)
            .padding(.bottom, VFSpace.bottomInset)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

/// A round secondary transport button with a small tracked label ("MARK", "PAUSE").
private struct TransportButton: View {
    let title: String
    let diameter: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(.custom(VFFontName.sansBold, size: 11, relativeTo: .caption))
                .tracking(1.3)
                .foregroundStyle(VFColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 6)
                .frame(width: diameter, height: diameter)
                .background(VFColor.surface, in: Circle())
                .overlay { Circle().strokeBorder(VFColor.borderStrong, lineWidth: VFMetric.hairline) }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// Scrolling bars of recent input levels, mirrored around the centre line. A clap shows as a
/// spike; a bookmark shows as a marker with a dot on top.
struct WaveformView: View {
    let samples: [WaveformSample]
    let capacity: Int

    /// The warm amber from the speaker set: authored for both appearances and distinct from
    /// the accent bars.
    static let bookmarkColor = VFColor.speaker(2)

    var body: some View {
        Canvas { context, size in
            let count = max(capacity, 1)
            let slot = size.width / CGFloat(count)
            let barWidth = max(1, slot * 0.6)
            let midY = size.height / 2
            let minHeight: CGFloat = 3
            let flagSize: CGFloat = 6
            // Bars use the top/bottom inset so a flag never collides with a full-height bar.
            let barArea = size.height - flagSize * 2
            // Right-align so the newest sample sits at the right edge and older ones scroll left.
            let offset = count - samples.count
            for (index, sample) in samples.enumerated() {
                let x = CGFloat(index + offset) * slot + (slot - barWidth) / 2
                let height = max(minHeight, CGFloat(min(max(sample.level, 0), 1)) * barArea)
                let rect = CGRect(x: x, y: midY - height / 2, width: barWidth, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(VFColor.accent))

                if sample.isBookmark {
                    let centerX = x + barWidth / 2
                    let line = CGRect(x: centerX - 0.5, y: flagSize, width: 1, height: size.height - flagSize)
                    context.fill(Path(line), with: .color(Self.bookmarkColor))
                    let flag = CGRect(x: centerX - flagSize / 2, y: 0, width: flagSize, height: flagSize)
                    context.fill(Path(ellipseIn: flag), with: .color(Self.bookmarkColor))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Horizontal level bar, 0...1.
struct LevelMeter: View {
    let level: Float
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(VFColor.borderStrong)
                Capsule()
                    .fill(level > 0.9 ? VFColor.danger : VFColor.accent)
                    .frame(width: proxy.size.width * CGFloat(min(max(level, 0), 1)))
                    .animation(reduceMotion ? nil : Animation.linear(duration: 0.1), value: level)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Input level")
        .accessibilityValue(level > 0.9 ? "\(Int(level * 100)) percent, too loud" : "\(Int(level * 100)) percent")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

struct LowDiskBanner: View {
    let availableBytes: Int64

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(VFColor.danger)
                .accessibilityHidden(true)
            Text("Low storage: about \(remainingText) of recording left.")
                .vfText(VFText.snippet, color: VFColor.textPrimary)
        }
        .padding(.horizontal, VFSpace.cardPaddingH)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VFColor.surface, in: RoundedRectangle(cornerRadius: VFRadius.block, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: VFRadius.block, style: .continuous)
                .strokeBorder(VFColor.danger.opacity(0.5), lineWidth: VFMetric.hairline)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("recorder.lowDisk")
    }

    private var remainingText: String {
        let seconds = DiskSpacePolicy.secondsRemaining(availableBytes: availableBytes)
        return Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}

#Preview("Idle") {
    RecorderView()
        .environment(\.services, .fakes())
        .modelContainer(PreviewData.container(populated: false))
}

/// The microphone picker. Reads only the input-related state, so it re-renders on route changes
/// and taps, never on the recorder's 100 ms snapshots (see DECISIONS 2026-09-18).
private struct MicrophoneMenu: View {
    let viewModel: RecorderViewModel
    /// The small capsule for the running screen; the full 60 pt row before recording.
    let compact: Bool

    var body: some View {
        if !viewModel.inputs.isEmpty {
            Menu {
                ForEach(viewModel.inputs) { input in
                    Button {
                        Task { await viewModel.selectInput(id: input.id) }
                    } label: {
                        if input.id == viewModel.selectedInputID {
                            Label(input.name, systemImage: "checkmark")
                        } else {
                            Text(input.name)
                        }
                    }
                }
                Divider()
                Button {
                    Task { await viewModel.selectInput(id: nil) }
                } label: {
                    if viewModel.inputChoice == .automatic {
                        Label("Automatic", systemImage: "checkmark")
                    } else {
                        Text("Automatic")
                    }
                }
            } label: {
                if compact {
                    HStack(spacing: 6) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text(selectedInputName)
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .vfText(VFText.meta, color: VFColor.textSecondary)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 32)
                    .background(VFColor.surface, in: Capsule())
                    .overlay { Capsule().strokeBorder(VFColor.border, lineWidth: VFMetric.hairline) }
                    .frame(minHeight: VFMetric.minHit)
                } else {
                    VFPickerRowLabel(eyebrow: "Microphone", value: selectedInputName, systemName: "mic.fill")
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Microphone: \(selectedInputName)")
            .accessibilityIdentifier("recorder.inputPicker")
        }
    }

    private var selectedInputName: String {
        if let selected = viewModel.inputs.first(where: { $0.id == viewModel.selectedInputID }) {
            return selected.name
        }
        return viewModel.inputChoice == .automatic ? "Automatic" : "iPhone Microphone"
    }
}

/// The quick labels offered for a few seconds after Mark (v1.1 plan item 1). Its own view that
/// reads only the labelable mark, so the 100 ms timer redraws don't rebuild it under the finger.
private struct MarkLabelChips: View {
    let viewModel: RecorderViewModel

    var body: some View {
        if viewModel.labelableMark != nil {
            HStack(spacing: 8) {
                ForEach(Bookmark.quickLabels, id: \.self) { label in
                    VFChip(label, isSelected: false) {
                        viewModel.labelLastMark(label)
                    }
                    .accessibilityHint("Labels the mark you just added")
                    .accessibilityIdentifier("recorder.markLabel.\(label)")
                }
            }
            .transition(.opacity)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Label this mark")
        }
    }
}

/// The summary template picker, offered before recording (design spec §4 Record — ready).
private struct TemplateMenu: View {
    let viewModel: RecorderViewModel

    var body: some View {
        Menu {
            ForEach(TemplateID.allCases) { template in
                Button {
                    viewModel.selectTemplate(template)
                } label: {
                    if template == viewModel.selectedTemplate {
                        Label(template.displayName, systemImage: "checkmark")
                    } else {
                        Text(template.displayName)
                    }
                }
            }
        } label: {
            VFPickerRowLabel(eyebrow: "Summary template", value: viewModel.selectedTemplate.displayName, systemName: "text.document")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Summary template: \(viewModel.selectedTemplate.displayName)")
        .accessibilityIdentifier("recorder.templatePicker")
    }
}
