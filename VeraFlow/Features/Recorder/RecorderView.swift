import SwiftUI
import SwiftData
import AVFoundation

public struct RecorderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @AppStorage("consentReminderEnabled") private var consentReminderEnabled = true
    @AppStorage("dontShowConsentAgain") private var dontShowConsentAgain = false
    
    private let recorderService: AudioRecorderServiceProtocol
    
    @State private var isRecording: Bool = false
    @State private var isPaused: Bool = false
    @State private var isInterrupted: Bool = false
    @State private var elapsed: TimeInterval = 0
    @State private var powerLevels: [Float] = Array(repeating: 0.05, count: 24)
    @State private var currentRecording: Recording? = nil
    @State private var showConsentSheet: Bool = false
    @State private var bookmarkAddedNotice: Bool = false
    @State private var errorMessage: String? = nil
    @State private var metricsTask: Task<Void, Never>? = nil
    
    public init(recorderService: AudioRecorderServiceProtocol = AudioRecorderService()) {
        self.recorderService = recorderService
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                // Interruption or Error Banner (§8.3)
                if isInterrupted {
                    HStack(spacing: 12) {
                        Image(systemName: "phone.down.circle.fill")
                            .font(.title2)
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Recording Interrupted")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("Call ended. Tap Resume to continue recording.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Resume") {
                            resumeRecording()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                } else if let errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .padding(.horizontal)
                }
                
                Spacer()
                
                // Live Timer Display
                VStack(spacing: 8) {
                    Text(formatTime(elapsed))
                        .font(.system(size: 64, weight: .light, design: .monospaced))
                    
                    Text(recordingStatusText)
                        .font(.subheadline)
                        .foregroundColor(statusColor)
                }
                
                // Dynamic Audio Waveform Visualizer
                HStack(spacing: 5) {
                    ForEach(0..<powerLevels.count, id: \.self) { index in
                        let level = CGFloat(powerLevels[index])
                        RoundedRectangle(cornerRadius: 3)
                            .fill(waveformColor(for: index))
                            .frame(width: 5, height: max(8, level * 72))
                            .animation(.easeOut(duration: 0.12), value: level)
                    }
                }
                .frame(height: 80)
                .padding(.horizontal)
                
                // Bookmark Added Toast
                if bookmarkAddedNotice {
                    Text("Bookmark added")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .transition(.opacity)
                }
                
                Spacer()
                
                // Live Controls
                if isRecording {
                    HStack(spacing: 36) {
                        // Add Bookmark Button
                        Button {
                            flagBookmark()
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "bookmark.circle.fill")
                                    .font(.system(size: 38))
                                    .foregroundColor(.blue)
                                Text("Bookmark")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // Stop Button (Finalize)
                        Button {
                            stopRecording()
                        } label: {
                            ZStack {
                                Circle()
                                    .stroke(Color.red, lineWidth: 4)
                                    .frame(width: 78, height: 78)
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.red)
                                    .frame(width: 32, height: 32)
                            }
                        }
                        
                        // Pause / Resume Button
                        Button {
                            if isPaused {
                                resumeRecording()
                            } else {
                                pauseRecording()
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: isPaused ? "play.circle.fill" : "pause.circle.fill")
                                    .font(.system(size: 38))
                                    .foregroundColor(.primary)
                                Text(isPaused ? "Resume" : "Pause")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.bottom, 36)
                } else {
                    // Big Record Button
                    Button {
                        if consentReminderEnabled && !dontShowConsentAgain {
                            showConsentSheet = true
                        } else {
                            startRecording()
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .stroke(Color.red, lineWidth: 4)
                                .frame(width: 82, height: 82)
                            Circle()
                                .fill(Color.red)
                                .frame(width: 66, height: 66)
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Record Meeting")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isRecording ? "Cancel" : "Close") {
                        if isRecording {
                            cancelRecording()
                        }
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showConsentSheet) {
                ConsentReminderSheet(onConfirm: {
                    showConsentSheet = false
                    startRecording()
                })
            }
        }
    }
    
    // MARK: - Recording Actions
    
    private func startRecording() {
        errorMessage = nil
        let sessionID = UUID()
        let sessionDir = AppConstants.recordingsDirectoryURL.appendingPathComponent(sessionID.uuidString, isDirectory: true)
        
        let initialTitle = defaultTitle()
        let recordingModel = Recording(
            id: sessionID,
            title: initialTitle,
            createdAt: Date(),
            duration: 0,
            audioFileName: "",
            source: .recorded,
            stage: .recording // Crash-safe in-progress marker (§8.2)
        )
        
        modelContext.insert(recordingModel)
        try? modelContext.save()
        currentRecording = recordingModel
        
        Task {
            do {
                let fileURL = try await recorderService.startRecording(targetDirectory: sessionDir)
                await MainActor.run {
                    recordingModel.audioFileName = fileURL.lastPathComponent
                    try? modelContext.save()
                    isRecording = true
                    isPaused = false
                    isInterrupted = false
                    startObservingMetrics()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    modelContext.delete(recordingModel)
                    try? modelContext.save()
                }
            }
        }
    }
    
    private func pauseRecording() {
        Task {
            try? await recorderService.pauseRecording()
            await MainActor.run {
                isPaused = true
            }
        }
    }
    
    private func resumeRecording() {
        Task {
            try? await recorderService.resumeRecording()
            await MainActor.run {
                isPaused = false
                isInterrupted = false
            }
        }
    }
    
    private func stopRecording() {
        metricsTask?.cancel()
        metricsTask = nil
        
        Task {
            do {
                let (fileURL, finalDuration) = try await recorderService.stopRecording()
                await MainActor.run {
                    if let recording = currentRecording {
                        recording.duration = finalDuration
                        recording.audioFileName = fileURL.lastPathComponent
                        recording.stage = .recorded
                        try? modelContext.save()
                    }
                    isRecording = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func cancelRecording() {
        metricsTask?.cancel()
        metricsTask = nil
        
        Task {
            _ = try? await recorderService.stopRecording()
            await MainActor.run {
                if let recording = currentRecording {
                    modelContext.delete(recording)
                    try? modelContext.save()
                }
                isRecording = false
                dismiss()
            }
        }
    }
    
    private func flagBookmark() {
        Task {
            let bookmark = await recorderService.addBookmark(note: "Flagged moment")
            await MainActor.run {
                currentRecording?.bookmarks.append(bookmark)
                try? modelContext.save()
                withAnimation {
                    bookmarkAddedNotice = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation {
                        bookmarkAddedNotice = false
                    }
                }
            }
        }
    }
    
    private func startObservingMetrics() {
        metricsTask?.cancel()
        metricsTask = Task {
            for await metrics in recorderService.metricsStream() {
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    self.elapsed = metrics.currentDuration
                    self.isInterrupted = metrics.isInterrupted
                    
                    // Push newest power level to waveform rolling buffer
                    var updated = powerLevels
                    updated.removeFirst()
                    updated.append(metrics.powerLevel)
                    self.powerLevels = updated
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private var recordingStatusText: String {
        if isInterrupted { return "Interrupted by Call" }
        if isPaused { return "Paused" }
        if isRecording { return "Recording audio locally..." }
        return "Ready to record"
    }
    
    private var statusColor: Color {
        if isInterrupted { return .orange }
        if isPaused { return .yellow }
        if isRecording { return .red }
        return .secondary
    }
    
    private func waveformColor(for index: Int) -> Color {
        if isInterrupted { return .orange }
        if isPaused { return .gray.opacity(0.4) }
        return isRecording ? Color.red.opacity(0.7 + Double(index % 3) * 0.1) : Color.gray.opacity(0.2)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
    
    private func defaultTitle() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return "Meeting · \(formatter.string(from: Date()))"
    }
}

#Preview {
    RecorderView(recorderService: FakeAudioRecorderService())
}
