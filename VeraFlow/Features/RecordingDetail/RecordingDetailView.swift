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
    private let summarizationService: SummarizationServiceProtocol = SummarizationService()
    private let purchaseService: PurchaseServiceProtocol = StoreKitPurchaseService()
    
    // Entitlement & Paywall State (§13)
    @State private var userEntitlement: UserEntitlementState? = nil
    @State private var isPaywallPresented: Bool = false
    
    // Transcription State
    @State private var isTranscribing: Bool = false
    @State private var transcriptionProgress: Double = 0
    @State private var transcriptionError: String? = nil
    
    // Diarization State (§10)
    @State private var isDiarizing: Bool = false
    @State private var diarizationError: String? = nil
    
    // Summarization State (§11)
    @State private var isSummarizing: Bool = false
    @State private var summarizationProgress: SummarizationProgress? = nil
    @State private var summarizationError: String? = nil
    @State private var selectedTemplate: TemplateID = .general
    @State private var isTemplateSheetPresented: Bool = false
    
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
    @State private var isExportSheetPresented: Bool = false
    
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
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    if selectedTab == .transcript && !recording.segments.isEmpty {
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
                    
                    // Export Action (§12, §16 M6)
                    Button {
                        isExportSheetPresented = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Export Recording")
                }
            }
        }
        .sheet(isPresented: $isExportSheetPresented) {
            ExportSheet(recording: recording)
        }
        .sheet(isPresented: $isPaywallPresented) {
            PaywallSheet(purchaseService: purchaseService)
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
            userEntitlement = await purchaseService.currentEntitlement()
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
                // Error Banner
                if let error = summarizationError {
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
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                
                // Active Summarization Progress Banner
                if isSummarizing {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text(summarizationProgress?.currentPhase ?? "Synthesizing On-Device Summary...")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Spacer()
                        }
                        if let prog = summarizationProgress, prog.totalChunks > 1 {
                            ProgressView(value: Double(prog.completedChunks), total: Double(prog.totalChunks))
                                .tint(.purple)
                            Text("Chunk \(prog.completedChunks) of \(prog.totalChunks)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color.purple.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                
                // Existing Summary View or Empty State
                if let summary = recording.summaries.last {
                    // Summary Header: Template Title & Re-run Menu
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: templateIcon(for: summary.templateID))
                                    .foregroundColor(.purple)
                                Text(summary.templateID.title)
                                    .font(.headline)
                            }
                            Text(summary.modelInfo)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        
                        // Re-run with Alternative Template Menu (§11.6)
                        Menu {
                            ForEach(TemplateID.allCases) { template in
                                Button {
                                    runSummarization(template: template)
                                } label: {
                                    Label(template.title, systemImage: templateIcon(for: template))
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Re-run")
                            }
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Capsule())
                        }
                        .disabled(isSummarizing || recording.segments.isEmpty)
                    }
                    .padding(.bottom, 4)
                    
                    // Template-Specific Payload Cards (§11.4)
                    renderTemplatePayload(summary: summary)
                    
                    // Action Items Card (§11.4)
                    renderActionItemsSection(summary: summary)
                    
                } else if !isSummarizing {
                    // Empty State: Select Template and Summarize
                    if recording.segments.isEmpty {
                        VStack(spacing: 16) {
                            Spacer()
                            Image(systemName: "sparkles")
                                .font(.system(size: 48))
                                .foregroundColor(.purple)
                            Text("Transcript Required for Summary")
                                .font(.headline)
                            Text("Transcribe audio first to generate a structured meeting summary, decisions, and action items.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Choose Summary Template")
                                .font(.headline)
                            
                            Picker("Template", selection: $selectedTemplate) {
                                ForEach(TemplateID.allCases) { template in
                                    Text(template.title).tag(template)
                                }
                            }
                            .pickerStyle(.menu)
                            .padding(.vertical, 4)
                            
                            Text(selectedTemplate.subtitle)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            if userEntitlement?.isLifetimeUnlocked == false {
                                HStack {
                                    Text("Free Summaries: \(userEntitlement?.freeSummariesRemaining ?? 3) of \(AppConstants.freeSummaryLimit) remaining")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Button("Upgrade") {
                                        isPaywallPresented = true
                                    }
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.purple)
                                }
                            }
                            
                            Button {
                                runSummarization(template: selectedTemplate)
                            } label: {
                                HStack {
                                    Image(systemName: "sparkles")
                                    Text("Generate AI Summary")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                        }
                        .padding()
                        .background(Color.purple.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Template Payload Renderers (§11.4)
    
    @ViewBuilder
    private func renderTemplatePayload(summary: SummaryRecord) -> some View {
        switch summary.templateID {
        case .general:
            if let output = try? JSONDecoder().decode(GeneralMeetingOutput.self, from: summary.payloadJSON) {
                VStack(alignment: .leading, spacing: 16) {
                    summarySectionCard(title: "Overview", icon: "doc.text") {
                        Text(output.overview)
                            .font(.body)
                    }
                    
                    if !output.keyDiscussionPoints.isEmpty {
                        summarySectionCard(title: "Key Discussion Points", icon: "list.bullet") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(output.keyDiscussionPoints, id: \.self) { point in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("•").foregroundColor(.purple)
                                        Text(point).font(.subheadline)
                                    }
                                }
                            }
                        }
                    }
                    
                    if !output.decisions.isEmpty {
                        summarySectionCard(title: "Decisions Made", icon: "checkmark.seal.fill") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(output.decisions, id: \.self) { decision in
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.caption)
                                        Text(decision).font(.subheadline)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
        case .client:
            if let output = try? JSONDecoder().decode(ClientConsultingOutput.self, from: summary.payloadJSON) {
                VStack(alignment: .leading, spacing: 16) {
                    summarySectionCard(title: "Executive Summary", icon: "briefcase.fill") {
                        Text(output.executiveSummary)
                            .font(.body)
                    }
                    
                    if !output.clientNeedsAndGoals.isEmpty {
                        summarySectionCard(title: "Client Needs & Goals", icon: "target") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(output.clientNeedsAndGoals, id: \.self) { goal in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("•").foregroundColor(.blue)
                                        Text(goal).font(.subheadline)
                                    }
                                }
                            }
                        }
                    }
                    
                    if !output.proposedSolutionsAndScope.isEmpty {
                        summarySectionCard(title: "Proposed Solutions & Scope", icon: "checkmark.shield.fill") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(output.proposedSolutionsAndScope, id: \.self) { solution in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("•").foregroundColor(.teal)
                                        Text(solution).font(.subheadline)
                                    }
                                }
                            }
                        }
                    }
                    
                    if !output.commercialsAndTimeline.isEmpty {
                        summarySectionCard(title: "Commercials & Timeline", icon: "calendar.badge.clock") {
                            Text(output.commercialsAndTimeline)
                                .font(.subheadline)
                        }
                    }
                }
            }
            
        case .walkthrough:
            if let output = try? JSONDecoder().decode(ContractorWalkthroughOutput.self, from: summary.payloadJSON) {
                VStack(alignment: .leading, spacing: 16) {
                    if !output.locationAndContext.isEmpty {
                        summarySectionCard(title: "Location & Site Context", icon: "mappin.and.ellipse") {
                            Text(output.locationAndContext)
                                .font(.body)
                        }
                    }
                    
                    if !output.scopeOfWork.isEmpty {
                        summarySectionCard(title: "Scope of Work & Measurements", icon: "ruler") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(output.scopeOfWork, id: \.self) { scope in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("•").foregroundColor(.orange)
                                        Text(scope).font(.subheadline)
                                    }
                                }
                            }
                        }
                    }
                    
                    if !output.materialsAndEquipment.isEmpty {
                        summarySectionCard(title: "Materials & Equipment", icon: "shippingbox.fill") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(output.materialsAndEquipment, id: \.self) { mat in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("•").foregroundColor(.brown)
                                        Text(mat).font(.subheadline)
                                    }
                                }
                            }
                        }
                    }
                    
                    if !output.hazardsAndConstraints.isEmpty {
                        summarySectionCard(title: "Site Hazards & Access Constraints", icon: "exclamationmark.shield.fill") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(output.hazardsAndConstraints, id: \.self) { hazard in
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.yellow)
                                            .font(.caption)
                                        Text(hazard).font(.subheadline)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func summarySectionCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(.purple)
                    .font(.caption)
                Text(title)
                    .font(.headline)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func renderActionItemsSection(summary: SummaryRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            let items = (try? JSONDecoder().decode([ActionItem].self, from: summary.actionItemsState)) ?? []
            let completedCount = items.filter(\.isCompleted).count
            
            HStack {
                Text("Action Items")
                    .font(.headline)
                if !items.isEmpty {
                    Text("(\(completedCount)/\(items.count))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if items.isEmpty {
                Text("No action items identified for this session.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Button {
                            toggleActionItemCompletion(summary: summary, itemID: item.id)
                        } label: {
                            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(item.isCompleted ? .green : .secondary)
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item.isCompleted ? "Mark incomplete: \(item.task)" : "Mark complete: \(item.task)")
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.task)
                                .font(.subheadline)
                                .strikethrough(item.isCompleted)
                                .foregroundColor(item.isCompleted ? .secondary : .primary)
                            
                            HStack(spacing: 8) {
                                let ownerName = displaySpeakerName(for: item.speakerKey) ?? item.owner
                                if !ownerName.isEmpty {
                                    Text(ownerName)
                                        .font(.caption)
                                        .foregroundColor(.purple)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.purple.opacity(0.1))
                                        .clipShape(Capsule())
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
                                        HStack(spacing: 2) {
                                            Image(systemName: "play.fill")
                                                .font(.system(size: 7))
                                            Text(item.timestamp)
                                                .font(.caption2)
                                                .monospacedDigit()
                                        }
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.12))
                                        .clipShape(Capsule())
                                    }
                                    .accessibilityLabel("Play audio at timestamp \(item.timestamp)")
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func templateIcon(for template: TemplateID) -> String {
        switch template {
        case .general: "person.3.fill"
        case .client: "briefcase.fill"
        case .walkthrough: "hammer.fill"
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
                .accessibilityLabel("Audio position")
                .accessibilityValue("\(formatTime(playerService.currentTime)) of \(formatTime(playerService.duration))")
                
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
                .accessibilityLabel("Rewind 15 seconds")
                
                Button {
                    playerService.togglePlayPause()
                } label: {
                    Image(systemName: playerService.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.blue)
                }
                .accessibilityLabel(playerService.isPlaying ? "Pause audio" : "Play audio")
                
                Button {
                    playerService.seek(to: playerService.currentTime + 15)
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.title3)
                }
                .accessibilityLabel("Fast forward 15 seconds")
                
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
                .accessibilityLabel("Playback speed")
                .accessibilityValue(String(format: "%.1fx", playerService.playbackRate))
                .accessibilityHint("Double tap to change playback speed")
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
    
    // MARK: - Summarization Execution (§11, §13)
    
    private func runSummarization(template: TemplateID) {
        guard !recording.segments.isEmpty else { return }
        
        Task {
            let canRun = await purchaseService.canGenerateSummary()
            if !canRun {
                await MainActor.run {
                    isPaywallPresented = true
                }
                return
            }
            
            await MainActor.run {
                isSummarizing = true
                summarizationError = nil
                summarizationProgress = nil
            }
            
            let segments = recording.segments.sorted(by: { $0.start < $1.start })
            let speakers = recording.speakers
            let duration = recording.duration
            let date = recording.createdAt
            
            do {
                let summary = try await summarizationService.generateSummary(
                    for: segments,
                    speakers: speakers,
                    recordingDuration: duration,
                    template: template,
                    recordingDate: date
                ) { progress in
                    Task { @MainActor in
                        self.summarizationProgress = progress
                    }
                }
                
                await purchaseService.recordSummaryGeneration()
                let entitlement = await purchaseService.currentEntitlement()
                
                await MainActor.run {
                    recording.summaries.append(summary)
                    recording.stage = .ready
                    self.userEntitlement = entitlement
                    try? modelContext.save()
                    isSummarizing = false
                }
            } catch {
                await MainActor.run {
                    self.summarizationError = error.localizedDescription
                    self.isSummarizing = false
                }
            }
        }
    }
    
    private func toggleActionItemCompletion(summary: SummaryRecord, itemID: UUID) {
        guard var items = try? JSONDecoder().decode([ActionItem].self, from: summary.actionItemsState) else { return }
        if let index = items.firstIndex(where: { $0.id == itemID }) {
            items[index].isCompleted.toggle()
            if let encoded = try? JSONEncoder().encode(items) {
                summary.actionItemsState = encoded
                try? modelContext.save()
            }
        }
    }
}

#Preview {
    NavigationStack {
        RecordingDetailView(recording: PreviewData.sampleRecording)
    }
}
