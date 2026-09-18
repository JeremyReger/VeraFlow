import SwiftData
import SwiftUI
import UIKit

/// Recording screen (SPEC §4.2): start, timer, level meter, pause/resume, stop, bookmarks, input picker.
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
    }
}

private struct RecorderContent: View {
    @Bindable var viewModel: RecorderViewModel
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .largeTitle) private var timerSize: CGFloat = 56
    @ScaledMetric(relativeTo: .largeTitle) private var startIconSize: CGFloat = 88
    @ScaledMetric(relativeTo: .title2) private var controlDiameter: CGFloat = 56
    @ScaledMetric(relativeTo: .title) private var stopDiameter: CGFloat = 72
    @Environment(\.openURL) private var openURL
    @State private var showsConsent = false

    var body: some View {
        NavigationStack {
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
            .navigationTitle("Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !viewModel.isActive, viewModel.phase != .naming {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
            }
        }
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
            // The status text changes colour and wording; VoiceOver hears it too (A-4).
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

    // MARK: Idle

    private var readyView: some View {
        VStack(spacing: 32) {
            Spacer()
            Button {
                // Consent reminder first (SPEC §14.2) unless the user turned it off.
                if AppPreferences.showsConsentReminder() {
                    showsConsent = true
                } else {
                    Task { await viewModel.start() }
                }
            } label: {
                VStack(spacing: 12) {
                    Image(systemName: "record.circle.fill")
                        .font(.system(size: startIconSize))
                        .foregroundStyle(.red)
                    Text("Start Recording")
                        .font(.headline)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start Recording")
            .accessibilityIdentifier("recorder.start")

            microphoneRow
            Text("Everything stays on this iPhone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
    }

    /// "Microphone: iPhone Microphone ▾". Its own view so the 10 Hz timer/level redraws of this
    /// screen don't rebuild the open menu, which dropped taps on device.
    private var microphoneRow: some View {
        MicrophoneMenu(viewModel: viewModel)
    }

    // MARK: Permission denied

    private var permissionDeniedView: some View {
        ContentUnavailableView {
            Label("Microphone access is off", systemImage: "mic.slash")
        } description: {
            Text("VeraFlow needs the microphone to record. Audio never leaves this iPhone.")
        } actions: {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .buttonStyle(.borderedProminent)
            Button("Try Again") { Task { await viewModel.start() } }
        }
    }

    // MARK: Recording / paused

    private var activeView: some View {
        VStack(spacing: 24) {
            if let bytes = viewModel.lowDiskBytes {
                LowDiskBanner(availableBytes: bytes)
            }

            Spacer()

            Text(viewModel.phase == .paused ? "Paused" : "Recording")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(viewModel.phase == .paused ? Color.secondary : Color.red)
                .accessibilityIdentifier("recorder.status")

            Text(Duration.seconds(viewModel.snapshot.elapsed), format: .time(pattern: .hourMinuteSecond))
                .font(.system(size: timerSize, weight: .light, design: .rounded))
                .monospacedDigit()
                .accessibilityLabel("Elapsed time")
                .accessibilityValue(SpokenFormat.duration(viewModel.snapshot.elapsed))
                .accessibilityAddTraits(.updatesFrequently)
                .accessibilityIdentifier("recorder.timer")

            WaveformView(samples: viewModel.levelHistory, capacity: RecorderViewModel.waveformSampleCount)
                .frame(height: 88)
                .padding(.horizontal, 24)

            LevelMeter(level: viewModel.snapshot.level)
                .frame(height: 6)
                .padding(.horizontal, 48)

            if viewModel.bookmarkCount > 0 {
                Text("^[\(viewModel.bookmarkCount) bookmark](inflect: true)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            microphoneRow

            if let notice = viewModel.notice {
                Text(notice)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }

            Spacer()

            HStack(spacing: 40) {
                Button {
                    Task { await viewModel.addBookmark() }
                } label: {
                    Label("Bookmark", systemImage: "flag.fill")
                        .labelStyle(.iconOnly)
                        .font(.title2)
                        .frame(width: controlDiameter, height: controlDiameter)
                }
                .buttonStyle(.bordered)
                .clipShape(Circle())
                .accessibilityLabel("Add Bookmark")
                .accessibilityIdentifier("recorder.bookmark")

                Button {
                    Task { await viewModel.stop() }
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.title)
                        .frame(width: stopDiameter, height: stopDiameter)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .clipShape(Circle())
                .accessibilityLabel("Stop")
                .accessibilityIdentifier("recorder.stop")

                if viewModel.phase == .paused {
                    Button {
                        Task { await viewModel.resume() }
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.title2)
                            .frame(width: controlDiameter, height: controlDiameter)
                    }
                    .buttonStyle(.bordered)
                    .clipShape(Circle())
                    .accessibilityLabel("Resume")
                    .accessibilityIdentifier("recorder.resume")
                } else {
                    Button {
                        Task { await viewModel.pause() }
                    } label: {
                        Image(systemName: "pause.fill")
                            .font(.title2)
                            .frame(width: controlDiameter, height: controlDiameter)
                    }
                    .buttonStyle(.bordered)
                    .clipShape(Circle())
                    .accessibilityLabel("Pause")
                    .accessibilityIdentifier("recorder.pause")
                }
            }
            .padding(.bottom, 32)
        }
        .padding()
    }

    // MARK: Naming

    private var namingView: some View {
        Form {
            Section("Name this recording") {
                TextField("Title", text: $viewModel.draftTitle)
                    .accessibilityIdentifier("recorder.title")
            }
            Section {
                LabeledContent("Length") {
                    Text(Duration.seconds(viewModel.recording?.duration ?? 0), format: .time(pattern: .hourMinuteSecond))
                }
                if viewModel.bookmarkCount > 0 {
                    LabeledContent("Bookmarks", value: "\(viewModel.bookmarkCount)")
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await viewModel.save() } }
                    .accessibilityIdentifier("recorder.save")
            }
        }
    }
}

/// Scrolling bars of recent input levels, mirrored around the centre line. A clap shows as a
/// spike; a bookmark shows as an orange marker with a flag on top.
struct WaveformView: View {
    let samples: [WaveformSample]
    let capacity: Int

    static let bookmarkColor = Color.orange

    var body: some View {
        Canvas { context, size in
            let count = max(capacity, 1)
            let slot = size.width / CGFloat(count)
            let barWidth = max(1, slot * 0.6)
            let midY = size.height / 2
            let minHeight: CGFloat = 2
            let flagSize: CGFloat = 6
            // Bars use the top/bottom inset so a flag never collides with a full-height bar.
            let barArea = size.height - flagSize * 2
            // Right-align so the newest sample sits at the right edge and older ones scroll left.
            let offset = count - samples.count
            for (index, sample) in samples.enumerated() {
                let x = CGFloat(index + offset) * slot + (slot - barWidth) / 2
                let height = max(minHeight, CGFloat(min(max(sample.level, 0), 1)) * barArea)
                let rect = CGRect(x: x, y: midY - height / 2, width: barWidth, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(.accentColor))

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
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(level > 0.9 ? VFColor.danger : Color.accentColor)
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
        Label {
            Text("Low storage: about \(remainingText) of recording left.")
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.footnote)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.yellow.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
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
/// and taps, never on the recorder's 100 ms snapshots.
private struct MicrophoneMenu: View {
    let viewModel: RecorderViewModel

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
                HStack(spacing: 6) {
                    Image(systemName: "mic.fill")
                    Text("Microphone")
                        .foregroundStyle(.secondary)
                    Text(selectedInputName)
                        .fontWeight(.medium)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.thinMaterial, in: Capsule())
            }
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
