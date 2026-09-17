import Testing
import Foundation
@testable import VeraFlow

@Suite("Service Fakes & Protocols Tests")
struct ServiceFakesTests {
    @Test("AudioRecorderService fake contract")
    func testAudioRecorderService() async throws {
        let recorder = FakeAudioRecorderService()
        let isRec = await recorder.isRecording
        #expect(!isRec)
        
        let tempDir = FileManager.default.temporaryDirectory
        let url = try await recorder.startRecording(targetDirectory: tempDir)
        #expect(url.lastPathComponent == "fake_recording.caf")
        
        let recordingNow = await recorder.isRecording
        #expect(recordingNow)
        
        let (stoppedURL, duration) = try await recorder.stopRecording()
        #expect(duration > 0)
        #expect(stoppedURL.pathExtension == "caf")
    }
    
    @Test("TranscriptionService fake contract")
    func testTranscriptionService() async throws {
        let transcriber = FakeTranscriptionService()
        let available = await transcriber.isAvailable()
        #expect(available)
        
        let dummyURL = URL(fileURLWithPath: "/tmp/dummy.caf")
        let result = try await transcriber.transcribeAudio(fileURL: dummyURL, locale: Locale(identifier: "en-US"), progress: nil)
        
        #expect(!result.words.isEmpty)
        #expect(!result.segments.isEmpty)
        #expect(result.engineUsed.contains("Transcriber"))
    }
    
    @Test("Diarization and Aligner fake contract")
    func testDiarizationAndAligner() async throws {
        let diarizer = FakeDiarizationService()
        let dummyURL = URL(fileURLWithPath: "/tmp/dummy.caf")
        let turns = try await diarizer.diarize(audioFileURL: dummyURL, expectedSpeakers: 2)
        #expect(turns.count == 2)
        
        let aligner = FakeTranscriptAligner()
        let words = [TimedWord(text: "Hello", start: 0, end: 1)]
        let alignment = aligner.align(words: words, turns: turns)
        #expect(alignment.segments.count == 1)
        #expect(alignment.speakers.count == 2)
    }
    
    @Test("DueDateResolver fake contract")
    func testDueDateResolver() {
        let resolver = FakeDueDateResolver()
        let refDate = Date()
        let resolvedTomorrow = resolver.resolve(dueText: "tomorrow", referenceDate: refDate)
        #expect(resolvedTomorrow.date != nil)
        
        let emptyResolved = resolver.resolve(dueText: "", referenceDate: refDate)
        #expect(emptyResolved.date == nil)
    }
    
    @Test("PurchaseService fake contract")
    func testPurchaseService() async throws {
        let purchase = FakePurchaseService(isUnlocked: false, freeUsed: 0)
        let initial = await purchase.currentEntitlement()
        #expect(!initial.isLifetimeUnlocked)
        #expect(initial.freeSummariesRemaining == 3)
        
        let canGen = await purchase.canGenerateSummary()
        #expect(canGen)
        
        await purchase.recordSummaryGeneration()
        let afterOne = await purchase.currentEntitlement()
        #expect(afterOne.freeSummariesUsed == 1)
        #expect(afterOne.freeSummariesRemaining == 2)
        
        let unlocked = try await purchase.purchaseLifetimeUnlock()
        #expect(unlocked)
        let finalState = await purchase.currentEntitlement()
        #expect(finalState.isLifetimeUnlocked)
    }
}
