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
    @Environment(\.openURL) private var openURL

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
        .task { await viewModel.loadInputs() }
        .onChange(of: viewModel.phase) { _, phase in
            if case .saved = phase { dismiss() }
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
                Task { await viewModel.start() }
            } label: {
                VStack(spacing: 12) {
                    Image(systemName: "record.circle.fill")
                        .font(.system(size: 88))
                        .foregroundStyle(.red)
                    Text("Start Recording")
                        .font(.headline)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start Recording")
            .accessibilityIdentifier("recorder.start")

            inputPicker
            Text("Everything stays on this iPhone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private var inputPicker: some View {
        if viewModel.inputs.count > 1 {
            Menu {
                Button("Automatic") { Task { await viewModel.selectInput(id: nil) } }
                Divider()
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
            } label: {
                Label(selectedInputName, systemImage: "mic")
            }
            .accessibilityIdentifier("recorder.inputPicker")
        }
    }

    private var selectedInputName: String {
        viewModel.inputs.first { $0.id == viewModel.selectedInputID }?.name ?? "Automatic microphone"
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
                .font(.system(size: 56, weight: .light, design: .rounded))
                .monospacedDigit()
                .accessibilityLabel("Elapsed time")
                .accessibilityIdentifier("recorder.timer")

            LevelMeter(level: viewModel.snapshot.level)
                .frame(height: 12)
                .padding(.horizontal, 48)

            if viewModel.bookmarkCount > 0 {
                Text("\(viewModel.bookmarkCount) bookmark\(viewModel.bookmarkCount == 1 ? "" : "s")")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

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
                        .frame(width: 56, height: 56)
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
                        .frame(width: 72, height: 72)
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
                            .frame(width: 56, height: 56)
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
                            .frame(width: 56, height: 56)
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

/// Horizontal level bar, 0...1.
struct LevelMeter: View {
    let level: Float

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(level > 0.9 ? Color.red : Color.accentColor)
                    .frame(width: proxy.size.width * CGFloat(min(max(level, 0), 1)))
                    .animation(.linear(duration: 0.1), value: level)
            }
        }
        .accessibilityLabel("Input level")
        .accessibilityValue("\(Int(level * 100)) percent")
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
