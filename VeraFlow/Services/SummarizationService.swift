import Foundation
import FoundationModels

/// Production on-device summarization engine using Apple Foundation Models (§11).
/// Features token budgeting, Map-Reduce chunking, and deterministic post-processing.
public final class SummarizationService: SummarizationServiceProtocol, Sendable {
    public static let singlePassWordLimit = 2000
    public static let targetChunkWordLimit = 1500
    public static let chunkWordOverlap = 150
    
    private let actionItemProcessor: ActionItemProcessor
    
    public init(actionItemProcessor: ActionItemProcessor = ActionItemProcessor()) {
        self.actionItemProcessor = actionItemProcessor
    }
    
    public func isAvailable() async -> Bool {
        return SystemLanguageModel.default.isAvailable
    }
    
    public func checkAvailability() -> (isReady: Bool, reason: String?) {
        switch SystemLanguageModel.default.availability {
        case .available:
            return (true, nil)
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return (false, "This device does not support on-device Apple Intelligence.")
            case .appleIntelligenceNotEnabled:
                return (false, "Apple Intelligence is turned off in Settings. Turn it on to generate AI summaries.")
            case .modelNotReady:
                return (false, "Apple Intelligence models are downloading. Please try again soon.")
            @unknown default:
                return (false, "Apple Intelligence is currently unavailable on this device.")
            }
        }
    }
    
    public func generateSummary(
        for segments: [AlignedSegment],
        speakers: [AlignedSpeaker],
        recordingDuration: TimeInterval,
        template: TemplateID,
        recordingDate: Date,
        progress: (@Sendable (SummarizationProgress) -> Void)?
    ) async throws -> SummarizationResult {
        guard !segments.isEmpty else {
            throw SummarizationError.emptyTranscript
        }
        
        let availability = checkAvailability()
        guard availability.isReady else {
            // If device cannot run Foundation Models, fall back to deterministic rule-based synthesis
            return try generateFallbackSummary(
                for: segments,
                speakers: speakers,
                recordingDuration: recordingDuration,
                template: template,
                recordingDate: recordingDate,
                reason: availability.reason ?? "Apple Intelligence Unavailable"
            )
        }
        
        let totalWords = segments.reduce(0) { $0 + $1.text.split(separator: " ").count }
        
        if totalWords <= Self.singlePassWordLimit {
            // Single-pass generation (§11.2)
            progress?(SummarizationProgress(completedChunks: 0, totalChunks: 1, currentPhase: "Synthesizing Summary"))
            return try await generateSinglePass(
                segments: segments,
                speakers: speakers,
                recordingDuration: recordingDuration,
                template: template,
                recordingDate: recordingDate,
                progress: progress
            )
        } else {
            // Map-Reduce chunking generation (§11.3)
            return try await generateMapReduce(
                segments: segments,
                speakers: speakers,
                recordingDuration: recordingDuration,
                template: template,
                recordingDate: recordingDate,
                progress: progress
            )
        }
    }
    
    // MARK: - Single-Pass Generation (§11.2)
    
    private func generateSinglePass(
        segments: [AlignedSegment],
        speakers: [AlignedSpeaker],
        recordingDuration: TimeInterval,
        template: TemplateID,
        recordingDate: Date,
        progress: (@Sendable (SummarizationProgress) -> Void)?
    ) async throws -> SummarizationResult {
        let transcriptText = formatTranscript(segments: segments, speakers: speakers)
        let instructions = makeInstructions(for: template, speakers: speakers)
        let session = LanguageModelSession(model: .default, instructions: instructions)
        
        let prompt = "Generate a structured meeting summary based strictly on this transcript:\n\n\(transcriptText)"
        
        let payloadData: Data
        var rawActions: [RawActionItem] = []
        let encoder = JSONEncoder()
        
        switch template {
        case .general:
            let response = try await session.respond(to: prompt, generating: GeneralMeetingOutput.self)
            payloadData = try encoder.encode(response.content)
            rawActions = response.content.actionItems
            
        case .client:
            let response = try await session.respond(to: prompt, generating: ClientConsultingOutput.self)
            payloadData = try encoder.encode(response.content)
            rawActions = response.content.actionItems
            
        case .walkthrough:
            let response = try await session.respond(to: prompt, generating: ContractorWalkthroughOutput.self)
            payloadData = try encoder.encode(response.content)
            rawActions = response.content.actionItems
        }
        
        // Post-process action items deterministically (§11.5)
        let processedActions = actionItemProcessor.process(
            rawItems: rawActions,
            referenceDate: recordingDate,
            speakers: speakers,
            segments: segments,
            recordingDuration: recordingDuration
        )
        
        progress?(SummarizationProgress(completedChunks: 1, totalChunks: 1, currentPhase: "Complete"))
        
        return SummarizationResult(
            templateID: template,
            payloadJSON: payloadData,
            actionItems: processedActions,
            modelInfo: "SystemLanguageModel (iOS 26)"
        )
    }
    
    // MARK: - Map-Reduce Generation (§11.3)
    
    private func generateMapReduce(
        segments: [AlignedSegment],
        speakers: [AlignedSpeaker],
        recordingDuration: TimeInterval,
        template: TemplateID,
        recordingDate: Date,
        progress: (@Sendable (SummarizationProgress) -> Void)?
    ) async throws -> SummarizationResult {
        let chunks = partitionIntoChunks(segments: segments, targetWordCount: Self.targetChunkWordLimit, overlapWords: Self.chunkWordOverlap)
        let totalSteps = chunks.count + 1
        
        var intermediateNotes: [String] = []
        var intermediateFacts: [String] = []
        var allCandidateActions: [RawActionItem] = []
        
        let mapInstructions = """
        You are an on-device executive assistant. Summarize this section of a transcript.
        Extract key facts, decisions, spoken measurements, and candidate action items.
        """
        
        // 1. MAP PHASE
        for (i, chunk) in chunks.enumerated() {
            progress?(SummarizationProgress(
                completedChunks: i,
                totalChunks: totalSteps,
                currentPhase: "Summarizing Section \(i + 1) of \(chunks.count)"
            ))
            
            let chunkTranscript = formatTranscript(segments: chunk, speakers: speakers)
            let mapSession = LanguageModelSession(model: .default, instructions: mapInstructions)
            let prompt = "Extract intermediate notes and candidate action items from this section:\n\n\(chunkTranscript)"
            
            do {
                let response = try await mapSession.respond(to: prompt, generating: IntermediateChunkOutput.self)
                intermediateNotes.append(contentsOf: response.content.summaryNotes)
                intermediateFacts.append(contentsOf: response.content.keyFacts)
                allCandidateActions.append(contentsOf: response.content.candidateActions)
            } catch {
                let fallbackNote = "Section \(i + 1): " + chunk.prefix(2).map(\.text).joined(separator: " ")
                intermediateNotes.append(fallbackNote)
            }
        }
        
        // 2. REDUCE PHASE
        progress?(SummarizationProgress(
            completedChunks: chunks.count,
            totalChunks: totalSteps,
            currentPhase: "Synthesizing Final Summary"
        ))
        
        let aggregatedText = """
        SECTION NOTES:
        \(intermediateNotes.map { "- " + $0 }.joined(separator: "\n"))
        
        KEY FACTS & MEASUREMENTS:
        \(intermediateFacts.map { "- " + $0 }.joined(separator: "\n"))
        
        CANDIDATE ACTION ITEMS:
        \(allCandidateActions.map { "- \($0.task) [Owner: \($0.owner), Due: \($0.dueText), Time: \($0.timestamp)]" }.joined(separator: "\n"))
        """
        
        let reduceInstructions = makeInstructions(for: template, speakers: speakers)
        let reduceSession = LanguageModelSession(model: .default, instructions: reduceInstructions)
        let finalPrompt = "Synthesize a final, unified summary from these aggregated meeting notes:\n\n\(aggregatedText)"
        
        let payloadData: Data
        var finalRawActions: [RawActionItem] = []
        let encoder = JSONEncoder()
        
        switch template {
        case .general:
            let response = try await reduceSession.respond(to: finalPrompt, generating: GeneralMeetingOutput.self)
            var content = response.content
            if content.actionItems.isEmpty { content.actionItems = allCandidateActions }
            payloadData = try encoder.encode(content)
            finalRawActions = content.actionItems
            
        case .client:
            let response = try await reduceSession.respond(to: finalPrompt, generating: ClientConsultingOutput.self)
            var content = response.content
            if content.actionItems.isEmpty { content.actionItems = allCandidateActions }
            payloadData = try encoder.encode(content)
            finalRawActions = content.actionItems
            
        case .walkthrough:
            let response = try await reduceSession.respond(to: finalPrompt, generating: ContractorWalkthroughOutput.self)
            var content = response.content
            if content.actionItems.isEmpty { content.actionItems = allCandidateActions }
            payloadData = try encoder.encode(content)
            finalRawActions = content.actionItems
        }
        
        let processedActions = actionItemProcessor.process(
            rawItems: finalRawActions,
            referenceDate: recordingDate,
            speakers: speakers,
            segments: segments,
            recordingDuration: recordingDuration
        )
        
        progress?(SummarizationProgress(completedChunks: totalSteps, totalChunks: totalSteps, currentPhase: "Complete"))
        
        return SummarizationResult(
            templateID: template,
            payloadJSON: payloadData,
            actionItems: processedActions,
            modelInfo: "SystemLanguageModel (Map-Reduce, \(chunks.count) chunks)"
        )
    }
    
    // MARK: - Prompt Instructions (§11.4)
    
    private func makeInstructions(for template: TemplateID, speakers: [AlignedSpeaker]) -> String {
        let speakerList = speakers.map { "\($0.key): \($0.displayName)" }.joined(separator: ", ")
        let speakerContext = speakerList.isEmpty ? "" : "Known Speakers in transcript: [\(speakerList)]."
        
        switch template {
        case .general:
            return """
            You are an expert executive meeting assistant running strictly on-device on iPhone.
            \(speakerContext)
            Rules:
            1. Overview: write a cohesive summary capturing the meeting thesis in 3-5 concise sentences.
            2. Key discussion points: bulleted, under 20 words each.
            3. Decisions: separate explicit decisions from ongoing discussion.
            4. Action items: each must start with an active verb, identify the owner (using speaker names or keys where known), specify any colloquial/explicit due date, and note the approximate timestamp (mm:ss).
            """
            
        case .client:
            return """
            You are a senior client relationship manager and consultant.
            \(speakerContext)
            Rules:
            1. Executive summary: tailored for client stakeholders and project leadership.
            2. Client needs & goals: capture requirements and objections in near-verbatim language.
            3. Proposed solutions & scope: list agreed solutions and clear boundaries of work.
            4. Commercials & timeline: note any stated budgets, fee structures, or target milestones.
            5. Action items: follow-up commitments attributed to each respective party.
            """
            
        case .walkthrough:
            return """
            You are an experienced construction job site superintendent.
            \(speakerContext)
            CRITICAL ACCURACY RULES:
            1. NEVER invent, estimate, or convert measurements. Only record exact spoken numbers and dimensions.
            2. Location: record site address, room names, or specific physical areas inspected.
            3. Scope of work: clean tasks with spoken dimensions.
            4. Materials & equipment: explicit items to order or bring to the site.
            5. Hazards: access obstacles, electrical/plumbing shutoffs, or safety constraints.
            6. Action items: trade assignments and completion deadlines.
            """
        }
    }
    
    // MARK: - Chunk Partitioning Helper (§11.3)
    
    public func partitionIntoChunks(
        segments: [AlignedSegment],
        targetWordCount: Int,
        overlapWords: Int
    ) -> [[AlignedSegment]] {
        guard !segments.isEmpty else { return [] }
        
        var chunks: [[AlignedSegment]] = []
        var currentChunk: [AlignedSegment] = []
        var currentWords = 0
        
        for seg in segments {
            let segWordCount = seg.text.split(separator: " ").count
            currentChunk.append(seg)
            currentWords += segWordCount
            
            if currentWords >= targetWordCount {
                chunks.append(currentChunk)
                
                // Keep overlap segments from end of current chunk
                var overlapChunk: [AlignedSegment] = []
                var overlapCount = 0
                for revSeg in currentChunk.reversed() {
                    let wCount = revSeg.text.split(separator: " ").count
                    overlapChunk.insert(revSeg, at: 0)
                    overlapCount += wCount
                    if overlapCount >= overlapWords { break }
                }
                
                currentChunk = overlapChunk
                currentWords = overlapCount
            }
        }
        
        if !currentChunk.isEmpty && (chunks.isEmpty || currentChunk.count > 1) {
            chunks.append(currentChunk)
        }
        
        return chunks.isEmpty ? [segments] : chunks
    }
    
    private func formatTranscript(segments: [AlignedSegment], speakers: [AlignedSpeaker]) -> String {
        segments.map { seg in
            let mins = Int(seg.start) / 60
            let secs = Int(seg.start) % 60
            let timeStr = String(format: "%02d:%02d", mins, secs)
            let speakerName = speakers.first(where: { $0.key == seg.speakerKey })?.displayName ?? seg.speakerKey ?? "Speaker"
            return "[\(timeStr)] \(speakerName): \(seg.text)"
        }.joined(separator: "\n")
    }
    
    // MARK: - Rule-Based Fallback Synthesis
    
    public func generateFallbackSummary(
        for segments: [AlignedSegment],
        speakers: [AlignedSpeaker],
        recordingDuration: TimeInterval,
        template: TemplateID,
        recordingDate: Date,
        reason: String
    ) throws -> SummarizationResult {
        let allSentences = segments.flatMap { $0.text.components(separatedBy: ". ") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        let overview = allSentences.prefix(3).joined(separator: ". ") + (allSentences.isEmpty ? "No transcript content available." : ".")
        let keyPoints = allSentences.prefix(5).map { String($0.prefix(100)) }
        
        var rawActions: [RawActionItem] = []
        let actionKeywords = ["need to", "will", "should", "action", "follow up", "send", "review", "schedule"]
        
        for seg in segments {
            let lower = seg.text.lowercased()
            for kw in actionKeywords {
                if lower.contains(kw) {
                    let mins = Int(seg.start) / 60
                    let secs = Int(seg.start) % 60
                    let timeStr = String(format: "%02d:%02d", mins, secs)
                    let spkName = speakers.first(where: { $0.key == seg.speakerKey })?.displayName ?? "Speaker"
                    rawActions.append(RawActionItem(
                        task: seg.text,
                        owner: spkName,
                        dueText: "upcoming",
                        timestamp: timeStr
                    ))
                    break
                }
            }
        }
        
        let processedActions = actionItemProcessor.process(
            rawItems: rawActions,
            referenceDate: recordingDate,
            speakers: speakers,
            segments: segments,
            recordingDuration: recordingDuration
        )
        
        let encoder = JSONEncoder()
        let payloadData: Data
        
        switch template {
        case .general:
            let out = GeneralMeetingOutput(
                overview: overview,
                keyDiscussionPoints: Array(keyPoints),
                decisions: ["Discussion items noted in transcript."],
                actionItems: rawActions
            )
            payloadData = try encoder.encode(out)
        case .client:
            let out = ClientConsultingOutput(
                executiveSummary: overview,
                clientNeedsAndGoals: Array(keyPoints.prefix(3)),
                proposedSolutionsAndScope: ["Review transcript notes for agreed deliverables."],
                commercialsAndTimeline: "Refer to recorded discussion.",
                actionItems: rawActions
            )
            payloadData = try encoder.encode(out)
        case .walkthrough:
            let out = ContractorWalkthroughOutput(
                locationAndContext: "Site walk-through discussion",
                scopeOfWork: Array(keyPoints),
                materialsAndEquipment: ["Check transcript for specified materials."],
                hazardsAndConstraints: ["Check transcript for stated constraints."],
                actionItems: rawActions
            )
            payloadData = try encoder.encode(out)
        }
        
        return SummarizationResult(
            templateID: template,
            payloadJSON: payloadData,
            actionItems: processedActions,
            modelInfo: "Deterministic Rule-Based Fallback (\(reason))"
        )
    }
}

public enum SummarizationError: LocalizedError, Sendable {
    case emptyTranscript
    case modelUnavailable(String)
    case generationFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .emptyTranscript: "Cannot generate summary for an empty transcript."
        case .modelUnavailable(let reason): "Apple Intelligence model is unavailable: \(reason)"
        case .generationFailed(let msg): "Summary generation failed: \(msg)"
        }
    }
}
