import Testing
import Foundation
import SwiftData
@testable import VeraFlow

@Suite("Polish, Sample Fixtures, & Accessibility Tests (§16 M9)")
struct PolishAndAccessibilityTests {
    
    @Test("TestFixtures makeGeneralMeeting generates valid recording with all domain models")
    @MainActor
    func testMakeGeneralMeeting() throws {
        let recording = TestFixtures.makeGeneralMeeting()
        
        #expect(recording.title == "Q4 Privacy & Engineering Review")
        #expect(recording.templateID == .general)
        #expect(recording.stage == .ready)
        #expect(recording.isFavorite == true)
        #expect(recording.segments.count >= 2)
        #expect(recording.speakers.count == 2)
        #expect(recording.bookmarks.count >= 1)
        #expect(recording.summaries.count == 1)
        
        guard let summary = recording.summaries.first else {
            Issue.record("Expected summary to exist")
            return
        }
        
        let output = try JSONDecoder().decode(GeneralMeetingOutput.self, from: summary.payloadJSON)
        #expect(output.overview.contains("VeraFlow privacy benchmarks"))
        #expect(output.decisions.count == 2)
        
        let actionItems = try JSONDecoder().decode([ActionItem].self, from: summary.actionItemsState)
        #expect(actionItems.count == 2)
        #expect(actionItems.contains(where: { $0.task.contains("zero-network policy") }))
    }
    
    @Test("TestFixtures makeClientMeeting generates valid consulting recording and output")
    @MainActor
    func testMakeClientMeeting() throws {
        let recording = TestFixtures.makeClientMeeting()
        
        #expect(recording.title.contains("Client Consultation"))
        #expect(recording.templateID == .client)
        #expect(recording.stage == .ready)
        #expect(recording.summaries.count == 1)
        
        guard let summary = recording.summaries.first else {
            Issue.record("Expected summary to exist")
            return
        }
        
        let output = try JSONDecoder().decode(ClientConsultingOutput.self, from: summary.payloadJSON)
        #expect(output.commercialsAndTimeline.contains("$0 recurring cloud fees"))
        #expect(output.clientNeedsAndGoals.count >= 1)
        
        let actionItems = try JSONDecoder().decode([ActionItem].self, from: summary.actionItemsState)
        #expect(actionItems.count == 1)
        #expect(actionItems.first?.owner.contains("Alex Mercer") == true)
    }
    
    @Test("TestFixtures makeContractorMeeting generates valid site walkthrough recording and output")
    @MainActor
    func testMakeContractorMeeting() throws {
        let recording = TestFixtures.makeContractorMeeting()
        
        #expect(recording.title.contains("Site Walkthrough"))
        #expect(recording.templateID == .walkthrough)
        #expect(recording.stage == .ready)
        #expect(recording.summaries.count == 1)
        
        guard let summary = recording.summaries.first else {
            Issue.record("Expected summary to exist")
            return
        }
        
        let output = try JSONDecoder().decode(ContractorWalkthroughOutput.self, from: summary.payloadJSON)
        #expect(output.locationAndContext.contains("Building 3"))
        #expect(output.materialsAndEquipment.count >= 2)
        
        let actionItems = try JSONDecoder().decode([ActionItem].self, from: summary.actionItemsState)
        #expect(actionItems.count == 1)
        #expect(actionItems.first?.task.contains("42U equipment racks") == true)
    }
    
    @Test("TestFixtures loadSampleRecordings inserts all 3 sample meetings into SwiftData ModelContext")
    @MainActor
    func testLoadSampleRecordings() throws {
        let schema = Schema([
            Recording.self,
            TranscriptSegment.self,
            Speaker.self,
            Bookmark.self,
            SummaryRecord.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        
        TestFixtures.loadSampleRecordings(into: context)
        
        let descriptor = FetchDescriptor<Recording>()
        let inserted = try context.fetch(descriptor)
        #expect(inserted.count == 3)
        
        let titles = Set(inserted.map(\.title))
        #expect(titles.contains("Q4 Privacy & Engineering Review"))
        #expect(titles.contains("Client Consultation — Acme Corp"))
        #expect(titles.contains("Site Walkthrough — Server Room B-12"))
    }
    
    @Test("Formatted durations for VoiceOver accessibility render correctly")
    func testDurationFormatting() {
        func formatDuration(_ duration: TimeInterval) -> String {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return String(format: "%d:%02d", minutes, seconds)
        }
        
        #expect(formatDuration(0) == "0:00")
        #expect(formatDuration(45) == "0:45")
        #expect(formatDuration(65) == "1:05")
        #expect(formatDuration(372) == "6:12")
        #expect(formatDuration(3600) == "60:00")
    }
}
