import Testing
import Foundation
import UIKit
@testable import VeraFlow

@Suite("Export Engine Tests (§12, §16 M6)")
struct ExportTests {
    
    @Test("Markdown export renders General template, action items, bookmarks, and transcript (§12.1)")
    @MainActor
    func testMarkdownExportGeneral() throws {
        let exportService = ExportService()
        let recording = PreviewData.sampleRecording
        
        // Populate payload for GeneralMeetingOutput
        let generalOutput = GeneralMeetingOutput(
            overview: "Strategic alignment on VeraFlow local engine architecture.",
            keyDiscussionPoints: [
                "100% on-device processing via Apple Speech and Foundation Models.",
                "Zero-data egress guarantee."
            ],
            decisions: [
                "Adopt SwiftData and Swift 6 complete concurrency.",
                "Target iOS 26 with backward compatibility."
            ],
            rawActionItems: []
        )
        
        let payloadData = try JSONEncoder().encode(generalOutput)
        recording.summaries.first?.payloadJSON = payloadData
        
        let markdownWithTranscript = exportService.exportMarkdown(recording: recording, includeTranscript: true)
        
        #expect(markdownWithTranscript.contains("# VeraFlow Kickoff & Architecture Alignment"))
        #expect(markdownWithTranscript.contains("## Overview"))
        #expect(markdownWithTranscript.contains("Strategic alignment on VeraFlow"))
        #expect(markdownWithTranscript.contains("## Key Discussion Points"))
        #expect(markdownWithTranscript.contains("100% on-device processing"))
        #expect(markdownWithTranscript.contains("## Decisions Made"))
        #expect(markdownWithTranscript.contains("Adopt SwiftData"))
        #expect(markdownWithTranscript.contains("## Action Items"))
        #expect(markdownWithTranscript.contains("- [ ] Review M0 foundation code — **Jeremy** • *(Due: tomorrow)* • `00:01`"))
        #expect(markdownWithTranscript.contains("## Bookmarks"))
        #expect(markdownWithTranscript.contains("`00:01` — Key Milestone Decision"))
        #expect(markdownWithTranscript.contains("## Full Transcript"))
        #expect(markdownWithTranscript.contains("**[00:00] Jeremy:** Let's finalize the VeraFlow architecture."))
        #expect(markdownWithTranscript.contains("*Generated privately on-device with VeraFlow.*"))
        
        let markdownWithoutTranscript = exportService.exportMarkdown(recording: recording, includeTranscript: false)
        #expect(!markdownWithoutTranscript.contains("## Full Transcript"))
    }
    
    @Test("Markdown export renders Client Consulting template (§12.1)")
    @MainActor
    func testMarkdownExportClient() throws {
        let exportService = ExportService()
        let recording = PreviewData.sampleRecording
        
        let clientOutput = ClientConsultingOutput(
            executiveSummary: "Client requested an audit of on-device transcription performance.",
            clientNeedsAndGoals: [
                "Comply with strict internal privacy and SOC2 policies.",
                "Eliminate per-minute cloud transcription costs."
            ],
            proposedSolutionsAndScope: [
                "Deploy VeraFlow with local Whisper/SpeechAnalyzer pipeline."
            ],
            commercialsAndTimeline: "$0 recurring cloud fees; initial rollout over 2 weeks.",
            rawActionItems: []
        )
        
        let payloadData = try JSONEncoder().encode(clientOutput)
        let clientSummary = SummaryRecord(
            createdAt: Date(),
            templateID: .client,
            payloadJSON: payloadData,
            actionItemsState: Data(),
            modelInfo: "SystemLanguageModel"
        )
        recording.summaries = [clientSummary]
        
        let md = exportService.exportMarkdown(recording: recording, includeTranscript: false)
        #expect(md.contains("## Executive Summary"))
        #expect(md.contains("Client requested an audit"))
        #expect(md.contains("## Client Needs & Goals"))
        #expect(md.contains("Comply with strict internal privacy"))
        #expect(md.contains("## Proposed Solutions & Scope"))
        #expect(md.contains("Deploy VeraFlow"))
        #expect(md.contains("## Commercials & Timeline"))
        #expect(md.contains("$0 recurring cloud fees"))
    }
    
    @Test("Markdown export renders Contractor Walkthrough template (§12.1)")
    @MainActor
    func testMarkdownExportContractor() throws {
        let exportService = ExportService()
        let recording = PreviewData.sampleRecording
        
        let walkthroughOutput = ContractorWalkthroughOutput(
            locationAndContext: "Main Server Room, Building 4",
            scopeOfWork: [
                "Install localized server racks and verify cabling.",
                "Inspect soundproofing dampeners."
            ],
            materialsAndEquipment: [
                "Cat6a shielded patch cables",
                "19-inch mounting hardware"
            ],
            hazardsAndConstraints: [
                "Overhead sprinkler lines require 18-inch clearance."
            ],
            rawActionItems: []
        )
        
        let payloadData = try JSONEncoder().encode(walkthroughOutput)
        let contractorSummary = SummaryRecord(
            createdAt: Date(),
            templateID: .walkthrough,
            payloadJSON: payloadData,
            actionItemsState: Data(),
            modelInfo: "SystemLanguageModel"
        )
        recording.summaries = [contractorSummary]
        
        let md = exportService.exportMarkdown(recording: recording, includeTranscript: false)
        #expect(md.contains("## Location & Context"))
        #expect(md.contains("Main Server Room, Building 4"))
        #expect(md.contains("## Scope of Work & Measurements"))
        #expect(md.contains("Install localized server racks"))
        #expect(md.contains("## Materials & Equipment"))
        #expect(md.contains("Cat6a shielded patch cables"))
        #expect(md.contains("## Hazards & Constraints"))
        #expect(md.contains("Overhead sprinkler lines require 18-inch clearance."))
    }
    
    @Test("Plain text export formats cleanly with standard text symbols (§12.2)")
    @MainActor
    func testPlainTextExport() throws {
        let exportService = ExportService()
        let recording = PreviewData.sampleRecording
        
        let plainText = exportService.exportPlainText(recording: recording, includeTranscript: true)
        
        #expect(plainText.contains("VERAFLOW KICKOFF & ARCHITECTURE ALIGNMENT"))
        #expect(plainText.contains("Date:"))
        #expect(plainText.contains("Duration:"))
        #expect(plainText.contains("ACTION ITEMS:"))
        #expect(plainText.contains("[ ] Review M0 foundation code"))
        #expect(plainText.contains("TRANSCRIPT:"))
        #expect(plainText.contains("[00:00] Jeremy: Let's finalize the VeraFlow architecture."))
    }
    
    @Test("PDF export produces valid PDF data with %PDF- magic bytes (§12.3)")
    @MainActor
    func testPDFExportMagicBytes() throws {
        let exportService = ExportService()
        let recording = PreviewData.sampleRecording
        
        let pdfData = exportService.exportPDF(recording: recording, includeTranscript: true)
        
        #expect(!pdfData.isEmpty)
        #expect(pdfData.count > 100)
        
        // Verify PDF Magic Bytes: "%PDF-" -> [0x25, 0x50, 0x44, 0x46, 0x2D]
        let magicBytes = [UInt8](pdfData.prefix(5))
        #expect(magicBytes == [0x25, 0x50, 0x44, 0x46, 0x2D])
    }
    
    @Test("Audio M4A export copies file when source is already m4a (§12.5)")
    @MainActor
    func testAudioM4ACopy() async throws {
        let exportService = ExportService()
        let recording = PreviewData.sampleRecording
        
        let tempDir = FileManager.default.temporaryDirectory
        let sourceURL = tempDir.appendingPathComponent("test_source_\(UUID().uuidString).m4a")
        let outputURL = tempDir.appendingPathComponent("test_output_\(UUID().uuidString).m4a")
        
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: outputURL)
        }
        
        let dummyData = "test audio content".data(using: .utf8)!
        try dummyData.write(to: sourceURL)
        
        try await exportService.exportAudioM4A(recording: recording, sourceAudioURL: sourceURL, outputURL: outputURL)
        
        #expect(FileManager.default.fileExists(atPath: outputURL.path))
        let copiedData = try Data(contentsOf: outputURL)
        #expect(copiedData == dummyData)
    }
    
    @Test("Audio M4A export throws error when source file is missing (§12.5)")
    @MainActor
    func testAudioM4AMissingSource() async {
        let exportService = ExportService()
        let recording = PreviewData.sampleRecording
        
        let missingURL = FileManager.default.temporaryDirectory.appendingPathComponent("non_existent_\(UUID().uuidString).caf")
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("dest_\(UUID().uuidString).m4a")
        
        do {
            try await exportService.exportAudioM4A(recording: recording, sourceAudioURL: missingURL, outputURL: outputURL)
            #expect(Bool(false), "Expected audioSourceFileNotFound error")
        } catch let error as ExportError {
            switch error {
            case .audioSourceFileNotFound:
                #expect(true)
            default:
                #expect(Bool(false), "Unexpected error type: \(error)")
            }
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }
    }
    
    @Test("FakeExportService simulates reminders and audio export for previews and UI testing (§12)")
    @MainActor
    func testFakeExportService() async throws {
        let fake = FakeExportService()
        let recording = PreviewData.sampleRecording
        
        let md = fake.exportMarkdown(recording: recording, includeTranscript: true)
        #expect(md.contains("# VeraFlow Kickoff"))
        
        let plain = fake.exportPlainText(recording: recording, includeTranscript: true)
        #expect(plain.contains("VERAFLOW KICKOFF"))
        
        let pdf = fake.exportPDF(recording: recording, includeTranscript: true)
        #expect(!pdf.isEmpty)
        
        let item = ActionItem(task: "Test task", owner: "Tester")
        let ids = try await fake.exportActionItemsToReminders(actionItems: [item], listTitle: nil)
        #expect(ids.count == 1)
        #expect(ids.first == "simulated-reminder-id")
    }
}
