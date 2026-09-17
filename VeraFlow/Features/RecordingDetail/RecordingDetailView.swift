import SwiftUI
import SwiftData
import AVFoundation

public struct RecordingDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let recording: Recording
    
    @State private var selectedTab: DetailTab = .transcript
    @State private var playerService = AudioPlayerService()
    
    private let transcriptionService: TranscriptionServiceProtocol = SpeechTranscriptionService()
    private let diarizationService: DiarizationServiceProtocol = FluidDiarizationService()
    private let aligner: TranscriptAlignerProtocol = TranscriptAligner()
    
    // Transcription State
    @State private var isTranscribing: Bool = false
    @State private var transcriptionProgress: Double = 0
    @State private var transcriptionError: String? = nil
    
    // Diarization State (§10)
    @State private var isDiarizing: Bool = false
    @State private var diarizationError: String? = nil
    
    // Speaker Editing & Renaming (§10.3)
    @State private var speakerToRename: Speaker? = nil
    @State private var renameSpeakerNameText: String = ""
    @State private var isRenameSpeakerAlertPresented: Bool = false
    
    // Speaker Merge Sheet (§10.3)
    @State private var speakerToMerge: Speaker? = nil
    @State private var isMergeSheetPresented: Bool = false
    
    // Transcript UI State
    @State private var isEditMode: Bool = false
    @State private var transcriptSearchText: String = ""
    
    public enum DetailTab: String, CaseIterable, Identifiable {
        case summary = "Summary"
        case transcript = "Transcript"
        case audio = "Audio"
        public var id: String { rawValue }
    }
    
    public init(recording: Recording) {
        self.recording = recording
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Segmented Tab Picker
            Picker("View", selection: $selectedTab) {
                ForEach(DetailTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            // Tab Content
            TabView(selection: $selectedTab) {
                summaryTab.tag(DetailTab.summary)
                transcriptTab.tag(DetailTab.transcript)
                audioTab.tag(DetailTab.audio)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            
            // Pinned Audio Player Bar (§4.4)
            pinnedAudioPlayerBar
        }
        .navigationTitle(recording.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if selectedTab == .transcript && !recording.segments.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        // Label Speakers Action (§10)
                        if recording.speakers.isEmpty {
                            Button {
                                runSpeakerDiarization()
                            } label: {
                                Label("Label Speakers", systemImage: "person.2")
                            }
                            .disabled(isDiarizing)
                        }
                        
                        // Edit Mode Button
                        Button(isEditMode ? "Done" : "Edit") {
                            isEditMode.toggle()
                            if !isEditMode {
                                try? modelContext.save()
                            }
                        }
                        .fontWeight(isEditMode ? .bold : .regular)
                    }
                }
            }
        }
        .alert("Rename Speaker", isPresented: $isRenameSpeakerAlertPresented) {
            TextField("Speaker Name", text: $renameSpeakerNameText)
            Button("Cancel", role: .cancel) {
                speakerToRename = nil
            }
            Button("Save") {
                applySpeakerRename()
            }
        } message: {
            Text("Enter a new display name for this speaker.")
        }
        .confirmationDialog(
            "Merge \(speakerToMerge?.displayName ?? "Speaker") into...",
            isPresented: $isMergeSheetPresented,
            titleVisibility: .visible
        ) {
            ForEach(otherSpeakers(than: speakerToMerge)) { target in
                Button(target.displayName) {
                    if let source = speakerToMerge {
                        mergeSpeaker(source: source, into: target)
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                speakerToMerge = nil
            }
        }
        .task {
            loadAudioPlayer()
        }
        .onDisappear {
            playerService.stop()
        }
    }
    
    // MARK: - Transcript Tab (§4.4, §10, §16 M4)
    
    private var transcriptTab: some View {
        VStack(spacing: 0) {
            // Status Banners
            if isTranscribing {
                VStack(spacing: 8) {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Transcribing audio on-device...")
                            .font(.subheadline)
                        Spacer()
                        Text("\(Int(transcriptionProgress * 100))%")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                    ProgressView(value: transcriptionProgress, total: 1.0)
                        .tint(.blue)
                }
                .padding()
                .background(Color.blue.opacity(0.08))
            } else if isDiarizing {
                HStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Identifying and labeling speakers on-device...")
                        .font(.subheadline)
                    Spacer()
                }
                .padding()
                .background(Color.purple.opacity(0.08))
            } else if let error = transcriptionError ?? diarizationError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding()
                .background(Color.red.opacity(0.08))
            }
            
            // Search Bar within Transcript
            if !recording.segments.isEmpty {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search transcript words...", text: $transcriptSearchText)
                        .font(.subheadline)
                    if !transcriptSearchText.isEmpty {
                        Button {
                            transcriptSearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
            
            // Transcript List or Empty State
            if recording.segments.isEmpty && !isTranscribing {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "waveform.and.mic")
                        .font(.system(size: 54))
                        .foregroundColor(.blue)
                    Text("Ready for On-Device Transcription")
                        .font(.headline)
                    Text("Transcribe with Apple's SpeechAnalyzer directly on your iPhone with zero cloud uploads.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    
                    Button {
                        startTranscription()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                            Text("Transcribe Audio")
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    Spacer()
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            // "Label Speakers" Banner if not yet diarized
                            if recording.speakers.isEmpty && !isDiarizing {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Speaker Labels Available")
                                            .font(.caption)
                                            .fontWeight(.bold)
                                        Text("Distinguish who spoke each sentence.")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Button("Label Speakers") {
                                        runSpeakerDiarization()
                                    }
                                    .font(.caption)
                                    .buttonStyle(.borderedProminent)
                                    .tint(.purple)
                                }
                                .padding(10)
                                .background(Color.purple.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            
                            let displayedSegments = filteredSegments()
                            ForEach(displayedSegments) { segment in
                                let isActive = isSegmentActive(segment)
                                let speakerObj = speaker(for: segment.speakerKey)
                                
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(spacing: 8) {
                                        // Interactive Speaker Chip with Rename & Merge Menu (§10.3)
                                        Menu {
                                            if let speakerObj {
                                                Button {
                                                    promptSpeakerRename(speakerObj)
                                                } label: {
                                                    Label("Rename \(speakerObj.displayName)", systemImage: "pencil")
                                                }
                                                
                                                if recording.speakers.count > 1 {
                                                    Button {
                                                        speakerToMerge = speakerObj
                                                        isMergeSheetPresented = true
                                                    } label: {
                                                        Label("Merge into another speaker...", systemImage: "arrow.triangle.merge")
                                                    }
                                                }
                                                
                                                Divider()
                                            }
                                            
                                            // Reassign Turn Menu (§10.3)
                                            Menu("Reassign Turn Speaker") {
                                                ForEach(recording.speakers) { sp in
                                                    Button(sp.displayName) {
                                                        segment.speakerKey = sp.key
                                                        try? modelContext.save()
                                                    }
                                                }
                                            }
                                        } label: {
                                            HStack(spacing: 4) {
                                                Circle()
                                                    .fill(speakerColor(for: speakerObj?.colorIndex ?? 0))
                                                    .frame(width: 8, height: 8)
                                                Text(speakerObj?.displayName ?? "Speaker")
                                                    .font(.caption)
                                                    .fontWeight(.bold)
                                                    .foregroundColor(.primary)
                                                Image(systemName: "chevron.down")
                                                    .font(.system(size: 8))
                                                    .foregroundColor(.secondary)
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(speakerColor(for: speakerObj?.colorIndex ?? 0).opacity(0.15))
                                            .clipShape(Capsule())
                                        }
                                        
                                        // Clickable Timestamp Chip (§4.4)
                                        Button {
                                            playerService.seek(to: segment.start)
                                            playerService.play()
                                        } label: {
                                            HStack(spacing: 2) {
                                                Image(systemName: "play.fill")
                                                    .font(.system(size: 8))
                                                Text(formatTime(segment.start))
                                                    .font(.caption2)
                                                    .monospacedDigit()
                                            }
                                            .foregroundColor(.secondary)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.secondary.opacity(0.12))
                                            .clipShape(Capsule())
                                        }
                                        
                                        Spacer()
                                    }
                                    
                                    // Text content (Editable or Read-only)
                                    if isEditMode {
                                        TextField("Segment text", text: Binding(
                                            get: { segment.text },
                                            set: { segment.text = $0 }
                                        ), axis: .vertical)
                                        .font(.body)
                                        .textFieldStyle(.roundedBorder)
                                    } else {
                                        Text(highlightText(segment.text, query: transcriptSearchText))
                                            .font(.body)
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                playerService.seek(to: segment.start)
                                                playerService.play()
                                            }
                                    }
                                }
                                .id(segment.id)
                                .padding(10)
                                .background(isActive ? Color.blue.opacity(0.12) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(isActive ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 1.5)
                                )
                            }
                        }
                        .padding()
                    }
                    .onChange(of: playerService.currentTime) { _, newTime in
                        if let active = recording.segments.first(where: { newTime >= $0.start && newTime <= $0.end }) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo(active.id, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Summary Tab (§11)
    
    private var summaryTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Overview")
                        .font(.headline)
                    Text("Local summary generated by Apple Foundation Models. Select a template and run summarization.")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Action Items")
                        .font(.headline)
                    
                    if let summary = recording.summaries.last,
                       let items = try? JSONDecoder().decode([ActionItem].self, from: summary.actionItemsState),
                       !items.isEmpty {
                        ForEach(items) { item in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(item.isCompleted ? .green : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.task)
                                        .font(.subheadline)
                                    HStack {
                                        let ownerName = displaySpeakerName(for: item.speakerKey) ?? item.owner
                                        if !ownerName.isEmpty {
                                            Text(ownerName)
                                                .font(.caption)
                                                .foregroundColor(.blue)
                                        }
                                        if !item.dueText.isEmpty {
                                            Text("• \(item.dueText)")
                                                .font(.caption)
                                                .foregroundColor(.orange)
                                        }
                                        if !item.timestamp.isEmpty {
                                            Button {
                                                if let time = item.audioTime {
                                                    playerService.seek(to: time)
                                                    playerService.play()
                                                }
                                            } label: {
                                                Text("▶︎ \(item.timestamp)")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } else {
                        Text("No action items yet. Tap Summarize to generate structured takeaways.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Audio Tab (§4.4)
    
    private var audioTab: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "waveform")
                .font(.system(size: 72))
                .foregroundColor(.accentColor)
            Text(recording.title)
                .font(.title2)
                .fontWeight(.medium)
            Text("Duration: \(formatTime(recording.duration))")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if !recording.bookmarks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Bookmarks")
                        .font(.headline)
                    ForEach(recording.bookmarks) { b in
                        HStack {
                            Text(formatTime(b.time))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundColor(.blue)
                            Text(b.note ?? "Bookmark")
                                .font(.caption)
                            Spacer()
                            Button("Play") {
                                playerService.seek(to: b.time)
                                playerService.play()
                            }
                            .font(.caption2)
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
            }
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Pinned Audio Player Bar (§4.4)
    
    private var pinnedAudioPlayerBar: some View {
        VStack(spacing: 6) {
            Divider()
            
            HStack(spacing: 8) {
                Text(formatTime(playerService.currentTime))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
                    .frame(width: 40, alignment: .leading)
                
                Slider(
                    value: Binding(
                        get: { playerService.currentTime },
                        set: { playerService.seek(to: $0) }
                    ),
                    in: 0...max(1.0, playerService.duration)
                )
                .tint(.blue)
                
                Text(formatTime(playerService.duration))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            
            HStack(spacing: 32) {
                Button {
                    playerService.seek(to: playerService.currentTime - 15)
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.title3)
                }
                
                Button {
                    playerService.togglePlayPause()
                } label: {
                    Image(systemName: playerService.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.blue)
                }
                
                Button {
                    playerService.seek(to: playerService.currentTime + 15)
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.title3)
                }
                
                Button {
                    playerService.cyclePlaybackRate()
                } label: {
                    Text(String(format: "%.1f×", playerService.playbackRate))
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            .foregroundColor(.primary)
            .padding(.bottom, 8)
        }
        .background(Color(uiColor: .systemBackground).opacity(0.95))
    }
    
    // MARK: - Actions & Diarization Logic (§10)
    
    private func loadAudioPlayer() {
        let audioFileURL = AppConstants.recordingsDirectoryURL
            .appendingPathComponent(recording.id.uuidString)
            .appendingPathComponent(recording.audioFileName)
        
        playerService.loadAudio(from: audioFileURL)
    }
    
    private func startTranscription() {
        let audioFileURL = AppConstants.recordingsDirectoryURL
            .appendingPathComponent(recording.id.uuidString)
            .appendingPathComponent(recording.audioFileName)
        
        isTranscribing = true
        transcriptionProgress = 0
        transcriptionError = nil
        
        Task {
            do {
                let locale = Locale(identifier: recording.localeIdentifier)
                let result = try await transcriptionService.transcribeAudio(
                    fileURL: audioFileURL,
                    locale: locale
                ) { progress in
                    Task { @MainActor in
                        self.transcriptionProgress = progress.fractionCompleted
                    }
                }
                
                await MainActor.run {
                    for (index, provSegment) in result.segments.enumerated() {
                        let seg = TranscriptSegment(
                            index: index,
                            start: provSegment.start,
                            end: provSegment.end,
                            text: provSegment.text,
                            words: provSegment.words
                        )
                        recording.segments.append(seg)
                    }
                    recording.stage = .transcribed
                    try? modelContext.save()
                    isTranscribing = false
                }
            } catch {
                await MainActor.run {
                    self.transcriptionError = error.localizedDescription
                    self.isTranscribing = false
                }
            }
        }
    }
    
    private func runSpeakerDiarization() {
        let audioFileURL = AppConstants.recordingsDirectoryURL
            .appendingPathComponent(recording.id.uuidString)
            .appendingPathComponent(recording.audioFileName)
        
        isDiarizing = true
        diarizationError = nil
        
        Task {
            do {
                // 1. Run diarization pipeline
                let turns = try await diarizationService.diarize(
                    audioFileURL: audioFileURL,
                    expectedSpeakers: nil
                )
                
                // 2. Gather all words in chronological order
                let allWords = recording.segments.flatMap(\.words).sorted(by: { $0.start < $1.start })
                
                // 3. Align with pure Swift TranscriptAligner (§10.2)
                let alignment = aligner.align(words: allWords, turns: turns)
                
                await MainActor.run {
                    // Update speakers
                    recording.speakers.removeAll()
                    for sp in alignment.speakers {
                        recording.speakers.append(Speaker(
                            key: sp.key,
                            displayName: sp.displayName,
                            colorIndex: sp.colorIndex
                        ))
                    }
                    
                    // Replace segments with aligned speaker segments
                    recording.segments.removeAll()
                    for seg in alignment.segments {
                        recording.segments.append(TranscriptSegment(
                            index: seg.index,
                            start: seg.start,
                            end: seg.end,
                            text: seg.text,
                            speakerKey: seg.speakerKey,
                            words: seg.words
                        ))
                    }
                    
                    recording.stage = .diarized
                    try? modelContext.save()
                    isDiarizing = false
                }
            } catch {
                await MainActor.run {
                    self.diarizationError = error.localizedDescription
                    self.isDiarizing = false
                }
            }
        }
    }
    
    // MARK: - Speaker Management (§10.3)
    
    private func promptSpeakerRename(_ speaker: Speaker) {
        speakerToRename = speaker
        renameSpeakerNameText = speaker.displayName
        isRenameSpeakerAlertPresented = true
    }
    
    private func applySpeakerRename() {
        guard let speaker = speakerToRename else { return }
        let trimmed = renameSpeakerNameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            speaker.displayName = trimmed
            try? modelContext.save()
        }
        speakerToRename = nil
        renameSpeakerNameText = ""
    }
    
    private func mergeSpeaker(source: Speaker, into target: Speaker) {
        // Reassign all segments with source key to target key
        for seg in recording.segments where seg.speakerKey == source.key {
            seg.speakerKey = target.key
        }
        // Remove source speaker
        recording.speakers.removeAll(where: { $0.key == source.key })
        try? modelContext.save()
        speakerToMerge = nil
    }
    
    private func otherSpeakers(than current: Speaker?) -> [Speaker] {
        guard let current else { return [] }
        return recording.speakers.filter { $0.key != current.key }
    }
    
    private func speaker(for key: String?) -> Speaker? {
        guard let key else { return nil }
        return recording.speakers.first(where: { $0.key == key })
    }
    
    private func displaySpeakerName(for key: String?) -> String? {
        guard let key else { return nil }
        return recording.speakers.first(where: { $0.key == key })?.displayName ?? key
    }
    
    private func speakerColor(for index: Int) -> Color {
        let colors: [Color] = [.blue, .purple, .orange, .teal, .indigo, .pink]
        return colors[index % colors.count]
    }
    
    private func isSegmentActive(_ segment: TranscriptSegment) -> Bool {
        let t = playerService.currentTime
        return t >= segment.start && t <= segment.end
    }
    
    private func filteredSegments() -> [TranscriptSegment] {
        if transcriptSearchText.isEmpty {
            return recording.segments.sorted(by: { $0.start < $1.start })
        }
        return recording.segments.filter {
            $0.text.localizedCaseInsensitiveContains(transcriptSearchText)
        }.sorted(by: { $0.start < $1.start })
    }
    
    private func highlightText(_ text: String, query: String) -> AttributedString {
        var attributed = AttributedString(text)
        guard !query.isEmpty else { return attributed }
        
        var searchRange = attributed.startIndex..<attributed.endIndex
        while let range = attributed[searchRange].range(of: query, options: .caseInsensitive) {
            attributed[range].backgroundColor = Color.yellow.opacity(0.35)
            attributed[range].inlinePresentationIntent = .stronglyEmphasized
            searchRange = range.upperBound..<attributed.endIndex
        }
        return attributed
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

#Preview {
    NavigationStack {
        RecordingDetailView(recording: PreviewData.sampleRecording)
    }
}
