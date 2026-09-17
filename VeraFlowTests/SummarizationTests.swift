import Testing
import Foundation
@testable import VeraFlow

@Suite("Summarization & Action Item Processing Tests (§11, §16 M5)")
struct SummarizationTests {
    
    @Test("ActionItemProcessor deduplicates similar tasks and merges metadata (§11.5 #1)")
    func testActionItemDeduplication() {
        let processor = ActionItemProcessor()
        
        let item1 = ActionItem(
            task: "Send updated architectural proposal to client",
            owner: "Jeremy",
            dueText: "",
            timestamp: "02:15"
        )
        let item2 = ActionItem(
            task: "to send updated architectural proposal to client", // leading prefix variation
            owner: "",
            dueText: "by Friday",
            timestamp: ""
        )
        let item3 = ActionItem(
            task: "Review subcontractor plumbing bids",
            owner: "David",
            dueText: "tomorrow",
            timestamp: "05:40"
        )
        
        let deduplicated = processor.deduplicate([item1, item2, item3])
        
        #expect(deduplicated.count == 2)
        let merged = deduplicated.first(where: { $0.task.contains("proposal") })
        #expect(merged != nil)
        #expect(merged?.owner == "Jeremy")
        #expect(merged?.dueText == "by Friday")
        #expect(merged?.timestamp == "02:15")
    }
    
    @Test("ActionItemProcessor resolves speaker keys from names and audio timestamps (§11.5 #3)")
    func testSpeakerKeyResolution() {
        let processor = ActionItemProcessor()
        
        let speakers = [
            AlignedSpeaker(key: "S1", displayName: "Alice Chen", colorIndex: 0),
            AlignedSpeaker(key: "S2", displayName: "Bob Builder", colorIndex: 1)
        ]
        
        let segments = [
            AlignedSegment(index: 0, start: 0.0, end: 30.0, text: "Intro", speakerKey: "S1"),
            AlignedSegment(index: 1, start: 30.0, end: 60.0, text: "Details", speakerKey: "S2")
        ]
        
        // 1. Direct name match
        let key1 = processor.resolveSpeakerKey(owner: "Alice Chen", audioTime: nil, speakers: speakers, segments: segments)
        #expect(key1 == "S1")
        
        // 2. Speaker 2 alias match
        let key2 = processor.resolveSpeakerKey(owner: "Speaker 2", audioTime: nil, speakers: speakers, segments: segments)
        #expect(key2 == "S2")
        
        // 3. Fallback to audioTime within segment window
        let key3 = processor.resolveSpeakerKey(owner: "Unknown", audioTime: 45.0, speakers: speakers, segments: segments)
        #expect(key3 == "S2")
    }
    
    @Test("ActionItemProcessor clamps timestamps to audio duration (§11.5 #4)")
    func testTimestampClamping() {
        let processor = ActionItemProcessor()
        
        let (formatted1, time1) = processor.parseAndClampTimestamp("01:30", maxDuration: 60.0)
        #expect(time1 == 60.0) // Clamped to max duration
        #expect(formatted1 == "01:00")
        
        let (formatted2, time2) = processor.parseAndClampTimestamp("[00:45]", maxDuration: 120.0)
        #expect(time2 == 45.0)
        #expect(formatted2 == "00:45")
    }
    
    @Test("Template output schemas encode and decode cleanly (§11.4)")
    func testTemplateOutputsEncoding() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        // General Meeting
        let gen = GeneralMeetingOutput(
            overview: "Overview text.",
            keyDiscussionPoints: ["Point 1", "Point 2"],
            decisions: ["Decision 1"],
            actionItems: [RawActionItem(task: "Task 1", owner: "S1", dueText: "soon", timestamp: "01:00")]
        )
        let genData = try encoder.encode(gen)
        let decodedGen = try decoder.decode(GeneralMeetingOutput.self, from: genData)
        #expect(decodedGen.overview == "Overview text.")
        #expect(decodedGen.decisions.count == 1)
        
        // Client Consulting
        let client = ClientConsultingOutput(
            executiveSummary: "Executive summary.",
            clientNeedsAndGoals: ["Goal 1"],
            proposedSolutionsAndScope: ["Solution 1"],
            commercialsAndTimeline: "$50k by Dec",
            actionItems: []
        )
        let clientData = try encoder.encode(client)
        let decodedClient = try decoder.decode(ClientConsultingOutput.self, from: clientData)
        #expect(decodedClient.commercialsAndTimeline == "$50k by Dec")
        
        // Contractor Walkthrough
        let walk = ContractorWalkthroughOutput(
            locationAndContext: "123 Main St",
            scopeOfWork: ["Framing 10x12"],
            materialsAndEquipment: ["Drywall"],
            hazardsAndConstraints: ["High voltage panel"],
            actionItems: []
        )
        let walkData = try encoder.encode(walk)
        let decodedWalk = try decoder.decode(ContractorWalkthroughOutput.self, from: walkData)
        #expect(decodedWalk.locationAndContext == "123 Main St")
    }
    
    @Test("SummarizationService partitions long transcripts into overlapping chunks (§11.3)")
    func testChunkPartitioning() {
        let service = SummarizationService()
        
        var segments: [AlignedSegment] = []
        // Generate segments totaling ~3000 words
        for i in 0..<30 {
            let sentence = (0..<100).map { "word\($0)" }.joined(separator: " ") + "."
            segments.append(AlignedSegment(
                index: i,
                start: Double(i * 10),
                end: Double((i + 1) * 10),
                text: sentence
            ))
        }
        
        let chunks = service.partitionIntoChunks(segments: segments, targetWordCount: 1500, overlapWords: 150)
        #expect(chunks.count >= 2)
        #expect(chunks.first?.count ?? 0 > 0)
    }
    
    @Test("SummarizationService fallback produces valid SummaryRecord on unavailable devices")
    func testFallbackSummaryGeneration() throws {
        let service = SummarizationService()
        let segments = [
            AlignedSegment(index: 0, start: 0.0, end: 10.0, text: "We decided to launch the project today."),
            AlignedSegment(index: 1, start: 10.0, end: 20.0, text: "Alice will review the documentation by tomorrow.")
        ]
        let speakers = [AlignedSpeaker(key: "S1", displayName: "Alice", colorIndex: 0)]
        
        let result = try service.generateFallbackSummary(
            for: segments,
            speakers: speakers,
            recordingDuration: 20.0,
            template: .general,
            recordingDate: Date(),
            reason: "Device Not Eligible"
        )
        
        #expect(result.templateID == .general)
        #expect(result.modelInfo.contains("Fallback"))
        
        let decodedOutput = try JSONDecoder().decode(GeneralMeetingOutput.self, from: result.payloadJSON)
        #expect(!decodedOutput.overview.isEmpty)
        #expect(!result.actionItems.isEmpty)
    }
}
