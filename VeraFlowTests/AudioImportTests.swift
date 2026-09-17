import Testing
import Foundation
import SwiftData
import AVFoundation
@testable import VeraFlow

@Suite("Audio Import & Library Management Tests (§16 M2)")
struct AudioImportTests {
    @Test("Format validation in AudioImportService")
    func testFormatValidation() {
        let service = AudioImportService()
        
        #expect(service.isSupportedAudioFile(at: URL(fileURLWithPath: "voice_memo.m4a")))
        #expect(service.isSupportedAudioFile(at: URL(fileURLWithPath: "interview.mp3")))
        #expect(service.isSupportedAudioFile(at: URL(fileURLWithPath: "track.wav")))
        #expect(service.isSupportedAudioFile(at: URL(fileURLWithPath: "sample.caf")))
        
        #expect(!service.isSupportedAudioFile(at: URL(fileURLWithPath: "document.pdf")))
        #expect(!service.isSupportedAudioFile(at: URL(fileURLWithPath: "video.mp4")))
        #expect(!service.isSupportedAudioFile(at: URL(fileURLWithPath: "notes.txt")))
    }
    
    @Test("AudioImportService imports audio and detects duration")
    func testAudioImportExecution() async throws {
        let service = AudioImportService()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("import_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // 1. Create a dummy valid CAF file
        let sourceURL = tempDir.appendingPathComponent("Team_Sync_Meeting.caf")
        let outputSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        let file = try AVAudioFile(
            forWriting: sourceURL,
            settings: outputSettings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 44100 * 2) else {
            Issue.record("Failed to create PCM buffer")
            return
        }
        buffer.frameLength = 44100 * 2 // 2 seconds
        try file.write(from: buffer)
        
        // 2. Import audio into isolated destination
        let destDir = tempDir.appendingPathComponent("imported_session")
        let (fileURL, duration, title) = try await service.importAudio(from: sourceURL, destinationDirectory: destDir)
        
        #expect(title == "Team Sync Meeting")
        #expect(duration >= 1.9)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        
        // Clean up
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    @Test("AudioImportService throws for unsupported formats")
    func testAudioImportUnsupported() async throws {
        let service = AudioImportService()
        let tempDir = FileManager.default.temporaryDirectory
        let dummyFile = tempDir.appendingPathComponent("test.pdf")
        try? "some text".write(to: dummyFile, atomically: true, encoding: .utf8)
        
        await #expect(throws: AudioImportError.self) {
            try await service.importAudio(from: dummyFile, destinationDirectory: tempDir)
        }
        
        try? FileManager.default.removeItem(at: dummyFile)
    }
    
    @Test("LibraryViewModel search, tag filtering, and sorting")
    func testLibraryViewModelOperations() {
        let vm = LibraryViewModel()
        
        let now = Date()
        let r1 = Recording(
            title: "Architecture Planning",
            createdAt: now.addingTimeInterval(-3600),
            duration: 300,
            audioFileName: "1.caf",
            tags: ["Architecture", "Team"]
        )
        r1.isFavorite = true
        
        let r2 = Recording(
            title: "Client Contractor Walkthrough",
            createdAt: now.addingTimeInterval(-1800),
            duration: 600,
            audioFileName: "2.caf",
            tags: ["Contractor"]
        )
        
        let r3 = Recording(
            title: "Quick Standup",
            createdAt: now,
            duration: 120,
            audioFileName: "3.caf",
            tags: ["Team"]
        )
        
        let allRecordings = [r1, r2, r3]
        
        // 1. Tag extraction
        let tags = vm.extractAllTags(from: allRecordings)
        #expect(tags == ["Architecture", "Contractor", "Team"])
        
        // 2. Search filter
        vm.searchText = "Contractor"
        let searchResults = vm.filterAndSortRecordings(allRecordings)
        #expect(searchResults.count == 1)
        #expect(searchResults.first?.title == "Client Contractor Walkthrough")
        vm.searchText = ""
        
        // 3. Tag filter
        vm.selectedTag = "Team"
        let tagResults = vm.filterAndSortRecordings(allRecordings)
        #expect(tagResults.count == 2)
        vm.selectedTag = nil
        
        // 4. Favorites filter
        vm.showFavoritesOnly = true
        let favResults = vm.filterAndSortRecordings(allRecordings)
        #expect(favResults.count == 1)
        #expect(favResults.first?.title == "Architecture Planning")
        vm.showFavoritesOnly = false
        
        // 5. Sorting: Alphabetical
        vm.sortOption = .alphabetical
        let alphaSorted = vm.filterAndSortRecordings(allRecordings)
        #expect(alphaSorted.map(\.title) == [
            "Architecture Planning",
            "Client Contractor Walkthrough",
            "Quick Standup"
        ])
        
        // 6. Sorting: Longest duration
        vm.sortOption = .longestDuration
        let durationSorted = vm.filterAndSortRecordings(allRecordings)
        #expect(durationSorted.map(\.duration) == [600, 300, 120])
        
        // 7. Renaming
        vm.promptRename(for: r1)
        #expect(vm.renameTitleText == "Architecture Planning")
        vm.renameTitleText = "VeraFlow Architecture"
        vm.applyRename()
        #expect(r1.title == "VeraFlow Architecture")
    }
}
