import Testing
import Foundation
import AVFoundation
@testable import VeraFlow

@Suite("SpeechAnalyzer Transcription & Paragraphing Tests (§9, §16 M3)")
struct TranscriptionTests {
    @Test("ParagraphingService splits on silence gap > 1.2s")
    func testParagraphingSilenceGap() {
        let service = ParagraphingService()
        
        let words = [
            TimedWord(text: "Hello", start: 0.0, end: 0.5),
            TimedWord(text: "world.", start: 0.6, end: 1.0),
            // 2.0 second pause
            TimedWord(text: "Welcome", start: 3.0, end: 3.5),
            TimedWord(text: "back.", start: 3.6, end: 4.0)
        ]
        
        let segments = service.buildSegments(from: words)
        #expect(segments.count == 2)
        #expect(segments[0].text == "Hello world.")
        #expect(segments[0].start == 0.0)
        #expect(segments[0].end == 1.0)
        #expect(segments[1].text == "Welcome back.")
        #expect(segments[1].start == 3.0)
        #expect(segments[1].end == 4.0)
    }
    
    @Test("ParagraphingService splits on sentence end + 25 words")
    func testParagraphingSentenceLength() {
        let service = ParagraphingService()
        
        var words: [TimedWord] = []
        // Generate 26 words ending in a period
        for i in 0..<26 {
            let punctuation = (i == 25) ? "." : ""
            words.append(TimedWord(text: "word\(i)\(punctuation)", start: Double(i) * 0.3, end: Double(i) * 0.3 + 0.2))
        }
        // Add next sentence
        words.append(TimedWord(text: "Next", start: 8.0, end: 8.2))
        words.append(TimedWord(text: "sentence.", start: 8.3, end: 8.5))
        
        let segments = service.buildSegments(from: words)
        #expect(segments.count == 2)
        #expect(segments[0].words.count == 26)
        #expect(segments[1].words.count == 2)
    }
    
    @Test("ParagraphingService splits on max segment duration > 45s")
    func testParagraphingDurationCap() {
        let service = ParagraphingService()
        
        let words = [
            TimedWord(text: "Start", start: 0.0, end: 1.0),
            TimedWord(text: "Middle", start: 45.1, end: 45.5),
            TimedWord(text: "End", start: 45.6, end: 46.0)
        ]
        
        let segments = service.buildSegments(from: words)
        #expect(segments.count >= 2)
    }
    
    @Test("ParagraphingService empty input handling")
    func testParagraphingEmpty() {
        let service = ParagraphingService()
        let segments = service.buildSegments(from: [])
        #expect(segments.isEmpty)
    }
    
    @Test("SpeechTranscriptionService throws for missing audio file")
    func testMissingAudioFile() async {
        let service = SpeechTranscriptionService()
        let missingURL = URL(fileURLWithPath: "/tmp/non_existent_audio_\(UUID().uuidString).caf")
        
        await #expect(throws: TranscriptionError.self) {
            try await service.transcribeAudio(fileURL: missingURL, locale: Locale(identifier: "en-US"), progress: nil)
        }
    }
    
    @Test("AudioPlayerService playback rate cycling and seek clamping")
    @MainActor
    func testAudioPlayerServiceControls() {
        let player = AudioPlayerService()
        
        #expect(player.playbackRate == 1.0)
        player.cyclePlaybackRate()
        #expect(player.playbackRate == 1.5)
        player.cyclePlaybackRate()
        #expect(player.playbackRate == 2.0)
        player.cyclePlaybackRate()
        #expect(player.playbackRate == 1.0)
        
        // Seek without loaded file safely clamps
        player.seek(to: -10)
        #expect(player.currentTime == 0)
    }
}
