import Foundation
import SwiftData

/// Comprehensive test fixtures providing realistic sample data for TestFlight betas and UI testing (§16 M9).
@MainActor
public enum TestFixtures {
    
    // MARK: - General Meeting Fixture
    
    public static func makeGeneralMeeting() -> Recording {
        let speaker1 = Speaker(key: "S1", displayName: "Sarah Connor", colorIndex: 0)
        let speaker2 = Speaker(key: "S2", displayName: "John Connor", colorIndex: 1)
        
        let words = [
            TimedWord(text: "Let's", start: 0.0, end: 0.3),
            TimedWord(text: "review", start: 0.4, end: 0.7),
            TimedWord(text: "our", start: 0.8, end: 0.9),
            TimedWord(text: "Q4", start: 1.0, end: 1.3),
            TimedWord(text: "privacy", start: 1.4, end: 1.8),
            TimedWord(text: "objectives.", start: 1.9, end: 2.5)
        ]
        
        let segment1 = TranscriptSegment(
            index: 0,
            start: 0.0,
            end: 2.5,
            text: "Let's review our Q4 privacy objectives.",
            speakerKey: "S1",
            words: words
        )
        
        let segment2 = TranscriptSegment(
            index: 1,
            start: 2.8,
            end: 6.2,
            text: "All customer telemetry has been migrated entirely to on-device Foundation Models.",
            speakerKey: "S2",
            words: []
        )
        
        let bookmark = Bookmark(time: 2.8, note: "Privacy milestone achieved")
        
        let actionItem1 = ActionItem(
            task: "Verify zero-network policy with automated security audit",
            owner: "Sarah Connor",
            speakerKey: "S1",
            dueText: "by Friday",
            resolvedDueDate: Calendar.current.date(byAdding: .day, value: 3, to: Date()),
            timestamp: "00:02",
            audioTime: 2.8,
            isCompleted: false
        )
        
        let actionItem2 = ActionItem(
            task: "Publish App Store Privacy Manifest",
            owner: "John Connor",
            speakerKey: "S2",
            dueText: "tomorrow",
            resolvedDueDate: Calendar.current.date(byAdding: .day, value: 1, to: Date()),
            timestamp: "00:05",
            audioTime: 5.0,
            isCompleted: true
        )
        
        let generalOutput = GeneralMeetingOutput(
            overview: "Review of VeraFlow privacy benchmarks and complete local Apple Intelligence migration.",
            keyDiscussionPoints: [
                "Zero data egress guarantee validated across all transcription paths.",
                "SpeechAnalyzer models run locally with fallback to DictationTranscriber."
            ],
            decisions: [
                "Approved production release for iOS 26 with Swift 6 strict concurrency.",
                "Maintain fair lifetime unlock monetization without subscription upsells."
            ],
            actionItems: []
        )
        
        let summary = SummaryRecord(
            createdAt: Date(),
            templateID: .general,
            payloadJSON: (try? JSONEncoder().encode(generalOutput)) ?? Data(),
            actionItemsState: (try? JSONEncoder().encode([actionItem1, actionItem2])) ?? Data(),
            modelInfo: "SystemLanguageModel (iOS 26)"
        )
        
        return Recording(
            title: "Q4 Privacy & Engineering Review",
            createdAt: Date().addingTimeInterval(-3600),
            duration: 372.0,
            audioFileName: "general_meeting.caf",
            source: .recorded,
            stage: .ready,
            localeIdentifier: "en-US",
            templateID: .general,
            tags: ["Engineering", "Privacy", "Q4"],
            isFavorite: true,
            segments: [segment1, segment2],
            speakers: [speaker1, speaker2],
            bookmarks: [bookmark],
            summaries: [summary]
        )
    }
    
    // MARK: - Client Consulting Fixture
    
    public static func makeClientMeeting() -> Recording {
        let speaker1 = Speaker(key: "S1", displayName: "Alex Mercer (Lead)", colorIndex: 2)
        let speaker2 = Speaker(key: "S2", displayName: "Dana Vance (Client)", colorIndex: 3)
        
        let segment = TranscriptSegment(
            index: 0,
            start: 0.0,
            end: 4.5,
            text: "We want to confirm the project scope and eliminate recurring monthly cloud fees.",
            speakerKey: "S2",
            words: []
        )
        
        let clientOutput = ClientConsultingOutput(
            executiveSummary: "Client requested an audit of on-device transcription performance and cost reduction options.",
            clientNeedsAndGoals: [
                "Comply with strict internal privacy and SOC2 data sovereignty requirements.",
                "Eliminate per-minute cloud API transcription bills."
            ],
            proposedSolutionsAndScope: [
                "Deploy VeraFlow with local Apple Neural Engine pipeline across all company iPhones.",
                "Integrate action items directly with Apple Reminders."
            ],
            commercialsAndTimeline: "$0 recurring cloud fees. Full team rollout completed in 10 business days.",
            actionItems: []
        )
        
        let actionItem = ActionItem(
            task: "Deliver pilot test build to client executive team",
            owner: "Alex Mercer (Lead)",
            speakerKey: "S1",
            dueText: "next week",
            resolvedDueDate: Calendar.current.date(byAdding: .day, value: 7, to: Date()),
            timestamp: "00:03",
            audioTime: 3.0,
            isCompleted: false
        )
        
        let summary = SummaryRecord(
            createdAt: Date(),
            templateID: .client,
            payloadJSON: (try? JSONEncoder().encode(clientOutput)) ?? Data(),
            actionItemsState: (try? JSONEncoder().encode([actionItem])) ?? Data(),
            modelInfo: "SystemLanguageModel"
        )
        
        return Recording(
            title: "Client Consultation — Acme Corp",
            createdAt: Date().addingTimeInterval(-86400),
            duration: 840.0,
            audioFileName: "client_meeting.caf",
            source: .recorded,
            stage: .ready,
            localeIdentifier: "en-US",
            templateID: .client,
            tags: ["Client", "Consulting", "Acme"],
            isFavorite: false,
            segments: [segment],
            speakers: [speaker1, speaker2],
            bookmarks: [],
            summaries: [summary]
        )
    }
    
    // MARK: - Contractor Walkthrough Fixture
    
    public static func makeContractorMeeting() -> Recording {
        let speaker1 = Speaker(key: "S1", displayName: "Dave (Electrician)", colorIndex: 4)
        let speaker2 = Speaker(key: "S2", displayName: "Marcus (GC)", colorIndex: 5)
        
        let segment = TranscriptSegment(
            index: 0,
            start: 0.0,
            end: 5.0,
            text: "We need 200 feet of Cat6a cable and two 42U server racks in the main IT closet.",
            speakerKey: "S1",
            words: []
        )
        
        let walkthroughOutput = ContractorWalkthroughOutput(
            locationAndContext: "Building 3, Basement Server Room B-12",
            scopeOfWork: [
                "Install two 42U equipment racks with dedicated 30A circuit.",
                "Pull 200 feet of shielded Cat6a patch cabling through existing conduit."
            ],
            materialsAndEquipment: [
                "Two 42U 19-inch equipment racks",
                "200 ft Cat6a CMR riser cable",
                "L5-30R locking receptacles"
            ],
            hazardsAndConstraints: [
                "Maintain 36-inch clear space in front of all electrical subpanels.",
                "Water main runs 24 inches above rack ceiling drop."
            ],
            actionItems: []
        )
        
        let actionItem = ActionItem(
            task: "Order 42U equipment racks and locking receptacles",
            owner: "Marcus (GC)",
            speakerKey: "S2",
            dueText: "tomorrow",
            resolvedDueDate: Calendar.current.date(byAdding: .day, value: 1, to: Date()),
            timestamp: "00:04",
            audioTime: 4.0,
            isCompleted: false
        )
        
        let summary = SummaryRecord(
            createdAt: Date(),
            templateID: .walkthrough,
            payloadJSON: (try? JSONEncoder().encode(walkthroughOutput)) ?? Data(),
            actionItemsState: (try? JSONEncoder().encode([actionItem])) ?? Data(),
            modelInfo: "SystemLanguageModel"
        )
        
        return Recording(
            title: "Site Walkthrough — Server Room B-12",
            createdAt: Date().addingTimeInterval(-172800),
            duration: 512.0,
            audioFileName: "contractor_walkthrough.caf",
            source: .recorded,
            stage: .ready,
            localeIdentifier: "en-US",
            templateID: .walkthrough,
            tags: ["Contractor", "Walkthrough", "Site"],
            isFavorite: true,
            segments: [segment],
            speakers: [speaker1, speaker2],
            bookmarks: [],
            summaries: [summary]
        )
    }
    
    // MARK: - SwiftData Loading Utility
    
    public static func loadSampleRecordings(into context: ModelContext) {
        let general = makeGeneralMeeting()
        let client = makeClientMeeting()
        let contractor = makeContractorMeeting()
        
        context.insert(general)
        context.insert(client)
        context.insert(contractor)
        try? context.save()
    }
}
