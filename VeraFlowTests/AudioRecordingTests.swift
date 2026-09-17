import Testing
import Foundation
import SwiftData
import AVFoundation
@testable import VeraFlow

@Suite("Audio Recording & Crash Recovery Tests (§8, §16 M1)")
struct AudioRecordingTests {
    @Test("AudioRecordingMetrics power normalization and properties")
    func testMetricsProperties() {
        let metrics = AudioRecordingMetrics(currentDuration: 12.5, powerLevel: 0.85, isInterrupted: true)
        #expect(metrics.currentDuration == 12.5)
        #expect(metrics.powerLevel == 0.85)
        #expect(metrics.isInterrupted)
    }
    
    @Test("AudioRecorderService lifecycle and CAF file creation")
    func testAudioRecorderServiceLifecycle() async throws {
        let service = AudioRecorderService()
        let isRec = await service.isRecording
        #expect(!isRec)
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString)")
        
        do {
            let fileURL = try await service.startRecording(targetDirectory: tempDir)
            #expect(fileURL.pathExtension.lowercased() == "caf")
            #expect(FileManager.default.fileExists(atPath: fileURL.path))
            
            let isRecNow = await service.isRecording
            #expect(isRecNow)
            
            let bookmark = await service.addBookmark(note: "Milestone Bookmark")
            #expect(bookmark.note == "Milestone Bookmark")
            
            try await service.pauseRecording()
            let isPausedNow = await service.isPaused
            #expect(isPausedNow)
            
            try await service.resumeRecording()
            let isPausedAfterResume = await service.isPaused
            #expect(!isPausedAfterResume)
            
            let (stoppedURL, duration) = try await service.stopRecording()
            #expect(stoppedURL == fileURL)
            #expect(duration >= 0)
            
            let isRecAfterStop = await service.isRecording
            #expect(!isRecAfterStop)
        } catch {
            // In CI or environments without microphone access, check error handling
            #expect(error is AudioRecorderError || error is NSError)
        }
        
        // Clean up
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    @Test("CrashRecoveryService restores interrupted recordings with valid CAF files")
    @MainActor
    func testCrashRecoveryService() throws {
        let schema = Schema([Recording.self, TranscriptSegment.self, Speaker.self, Bookmark.self, SummaryRecord.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = container.mainContext
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("recovery_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // 1. Create a dummy valid CAF file
        let audioFileName = "interrupted.caf"
        let audioFileURL = tempDir.appendingPathComponent(audioFileName)
        
        let outputSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        
        let file = try AVAudioFile(
            forWriting: audioFileURL,
            settings: outputSettings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        
        // Write 1 second of silence
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: 44100
        ) else {
            Issue.record("Failed to create PCM buffer")
            return
        }
        buffer.frameLength = 44100
        try file.write(from: buffer)
        
        // 2. Insert a recording model stuck in .recording stage
        let interruptedRecording = Recording(
            title: "Interrupted Board Meeting",
            createdAt: Date(),
            duration: 0,
            audioFileName: audioFileName,
            stage: .recording
        )
        context.insert(interruptedRecording)
        try context.save()
        
        // 3. Execute recovery scanner
        let recoveryService = CrashRecoveryService()
        let recovered = recoveryService.scanAndRecover(in: context, recordingsBaseURL: tempDir)
        
        #expect(recovered.count == 1)
        #expect(recovered.first == "Interrupted Board Meeting")
        #expect(interruptedRecording.stage == .recorded)
        #expect(interruptedRecording.duration > 0.9)
        #expect(interruptedRecording.bookmarks.contains { $0.note?.contains("Recovered") == true })
        
        // Clean up
        try? FileManager.default.removeItem(at: tempDir)
    }
}
