import Testing
import Foundation
@testable import VeraFlow

@Suite("TranscriptAligner & Speaker Labeling Tests (§10, §16 M4)")
struct TranscriptAlignerTests {
    
    @Test("Alternating two-speaker dialogue creates distinct segments and canonical keys")
    func testAlternatingTwoSpeakerDialogue() {
        let aligner = TranscriptAligner()
        
        let words = [
            TimedWord(text: "Hello", start: 0.0, end: 0.5),
            TimedWord(text: "Alice.", start: 0.6, end: 1.0),
            TimedWord(text: "Hi", start: 1.5, end: 1.8),
            TimedWord(text: "Bob.", start: 1.9, end: 2.3),
            TimedWord(text: "Good", start: 2.8, end: 3.1),
            TimedWord(text: "morning.", start: 3.2, end: 3.6)
        ]
        
        let turns = [
            SpeakerTurn(rawSpeakerID: "RAW_A", start: 0.0, end: 1.2),
            SpeakerTurn(rawSpeakerID: "RAW_B", start: 1.4, end: 2.5),
            SpeakerTurn(rawSpeakerID: "RAW_A", start: 2.7, end: 4.0)
        ]
        
        let result = aligner.align(words: words, turns: turns)
        
        #expect(result.speakers.count == 2)
        #expect(result.speakers[0].key == "S1")
        #expect(result.speakers[0].displayName == "Speaker 1")
        #expect(result.speakers[1].key == "S2")
        #expect(result.speakers[1].displayName == "Speaker 2")
        
        #expect(result.segments.count == 3)
        #expect(result.segments[0].speakerKey == "S1")
        #expect(result.segments[0].text == "Hello Alice.")
        #expect(result.segments[1].speakerKey == "S2")
        #expect(result.segments[1].text == "Hi Bob.")
        #expect(result.segments[2].speakerKey == "S1")
        #expect(result.segments[2].text == "Good morning.")
    }
    
    @Test("Word straddling two turns resolves to turn with largest temporal overlap (§10.2 #1)")
    func testWordStraddlingTwoTurnsOverlap() {
        let aligner = TranscriptAligner()
        
        // Word spans 1.0 to 1.5 (duration 0.5s)
        // Turn A: 0.0 to 1.2 (overlap 0.2s)
        // Turn B: 1.2 to 2.5 (overlap 0.3s) -> Turn B wins
        let words = [
            TimedWord(text: "Straddler", start: 1.0, end: 1.5)
        ]
        
        let turns = [
            SpeakerTurn(rawSpeakerID: "RAW_A", start: 0.0, end: 1.2),
            SpeakerTurn(rawSpeakerID: "RAW_B", start: 1.2, end: 2.5)
        ]
        
        let result = aligner.align(words: words, turns: turns)
        
        #expect(result.segments.count == 1)
        #expect(result.speakers.first?.key == "S1")
        // Since RAW_B had the largest overlap (0.3s vs 0.2s), RAW_B was first assigned and mapped to S1
        #expect(result.segments[0].speakerKey == "S1")
        #expect(result.segments[0].text == "Straddler")
    }
    
    @Test("Gap bridging: assigns nearest turn within 0.5s threshold (§10.2 #1)")
    func testGapBridgingWithinHalfSecond() {
        let aligner = TranscriptAligner()
        
        let turns = [
            SpeakerTurn(rawSpeakerID: "RAW_A", start: 0.0, end: 1.0),
            SpeakerTurn(rawSpeakerID: "RAW_B", start: 2.0, end: 3.0)
        ]
        
        // Word 1 (1.1 - 1.3): distance to Turn A is 0.1s, Turn B is 0.7s -> RAW_A
        // Word 2 (1.7 - 1.9): distance to Turn A is 0.7s, Turn B is 0.1s -> RAW_B
        let words = [
            TimedWord(text: "NearA", start: 1.1, end: 1.3),
            TimedWord(text: "NearB", start: 1.7, end: 1.9)
        ]
        
        let result = aligner.align(words: words, turns: turns)
        
        #expect(result.segments.count == 2)
        #expect(result.segments[0].text == "NearA")
        #expect(result.segments[0].speakerKey == "S1")
        #expect(result.segments[1].text == "NearB")
        #expect(result.segments[1].speakerKey == "S2")
    }
    
    @Test("Sandwiched runs of fewer than 3 words are smoothed into surrounding speaker (§10.2 #2)")
    func testSandwichedRunsSmoothing() {
        let aligner = TranscriptAligner()
        
        // RAW_A speaks 3 words, RAW_B speaks 2 words (sandwiched), RAW_A speaks 3 words
        let words = [
            TimedWord(text: "One", start: 0.0, end: 0.3),
            TimedWord(text: "two", start: 0.4, end: 0.7),
            TimedWord(text: "three.", start: 0.8, end: 1.1),
            TimedWord(text: "brief", start: 1.2, end: 1.4),   // Sandwiched run of 2 words (< 3)
            TimedWord(text: "cough", start: 1.5, end: 1.7),   // Sandwiched run of 2 words (< 3)
            TimedWord(text: "four", start: 1.8, end: 2.1),
            TimedWord(text: "five", start: 2.2, end: 2.5),
            TimedWord(text: "six.", start: 2.6, end: 2.9)
        ]
        
        let turns = [
            SpeakerTurn(rawSpeakerID: "RAW_A", start: 0.0, end: 1.15),
            SpeakerTurn(rawSpeakerID: "RAW_B", start: 1.16, end: 1.75),
            SpeakerTurn(rawSpeakerID: "RAW_A", start: 1.76, end: 3.0)
        ]
        
        let result = aligner.align(words: words, turns: turns)
        
        // Because the RAW_B run is only 2 words and surrounded by RAW_A,
        // it should be smoothed to RAW_A, resulting in 1 unified speaker S1.
        #expect(result.speakers.count == 1)
        #expect(result.speakers[0].key == "S1")
        #expect(result.segments.count == 1)
        #expect(result.segments[0].speakerKey == "S1")
        #expect(result.segments[0].words.count == 8)
    }
    
    @Test("Runs of 3 or more words are not smoothed away")
    func testThreeWordRunPreserved() {
        let aligner = TranscriptAligner()
        
        let words = [
            TimedWord(text: "One", start: 0.0, end: 0.3),
            TimedWord(text: "two", start: 0.4, end: 0.7),
            TimedWord(text: "three.", start: 0.8, end: 1.1),
            TimedWord(text: "now", start: 1.2, end: 1.4),
            TimedWord(text: "three", start: 1.5, end: 1.7),
            TimedWord(text: "words.", start: 1.8, end: 2.0),
            TimedWord(text: "four", start: 2.1, end: 2.4),
            TimedWord(text: "five", start: 2.5, end: 2.8),
            TimedWord(text: "six.", start: 2.9, end: 3.2)
        ]
        
        let turns = [
            SpeakerTurn(rawSpeakerID: "RAW_A", start: 0.0, end: 1.15),
            SpeakerTurn(rawSpeakerID: "RAW_B", start: 1.16, end: 2.05),
            SpeakerTurn(rawSpeakerID: "RAW_A", start: 2.06, end: 3.5)
        ]
        
        let result = aligner.align(words: words, turns: turns)
        
        #expect(result.speakers.count == 2)
        #expect(result.segments.count == 3)
        #expect(result.segments[1].speakerKey == "S2")
        #expect(result.segments[1].words.count == 3)
    }
    
    @Test("Canonical key mapping assigns S1...Sn in chronological order of first appearance (§10.2 #4)")
    func testCanonicalKeyMappingOrder() {
        let aligner = TranscriptAligner()
        
        let words = [
            TimedWord(text: "First", start: 0.0, end: 0.5),
            TimedWord(text: "Second", start: 1.0, end: 1.5),
            TimedWord(text: "Third", start: 2.0, end: 2.5)
        ]
        
        let turns = [
            SpeakerTurn(rawSpeakerID: "SPEAKER_ZEBRA", start: 0.0, end: 0.8),
            SpeakerTurn(rawSpeakerID: "SPEAKER_ALPHA", start: 0.9, end: 1.8),
            SpeakerTurn(rawSpeakerID: "SPEAKER_ZEBRA", start: 1.9, end: 2.8)
        ]
        
        let result = aligner.align(words: words, turns: turns)
        
        #expect(result.speakers.count == 2)
        #expect(result.speakers[0].key == "S1")
        #expect(result.speakers[1].key == "S2")
        // SPEAKER_ZEBRA was first -> S1, SPEAKER_ALPHA was second -> S2
        #expect(result.segments[0].speakerKey == "S1")
        #expect(result.segments[1].speakerKey == "S2")
        #expect(result.segments[2].speakerKey == "S1")
    }
    
    @Test("Empty words returns empty alignment result")
    func testEmptyWords() {
        let aligner = TranscriptAligner()
        let result = aligner.align(words: [], turns: [SpeakerTurn(rawSpeakerID: "SPK", start: 0, end: 1)])
        #expect(result.segments.isEmpty)
        #expect(result.speakers.isEmpty)
    }
    
    @Test("Speaker rename and merge mutation logic (§10.3)")
    func testSpeakerRenameAndMergeLogic() {
        var speakers = [
            Speaker(key: "S1", displayName: "Speaker 1", colorIndex: 0),
            Speaker(key: "S2", displayName: "Speaker 2", colorIndex: 1)
        ]
        
        var segments = [
            TranscriptSegment(index: 0, start: 0.0, end: 1.0, text: "Hello", speakerKey: "S1"),
            TranscriptSegment(index: 1, start: 1.1, end: 2.0, text: "Hi there", speakerKey: "S2"),
            TranscriptSegment(index: 2, start: 2.1, end: 3.0, text: "Welcome", speakerKey: "S1")
        ]
        
        // 1. Rename S1
        speakers[0].displayName = "Dr. Jane Smith"
        #expect(speakers[0].displayName == "Dr. Jane Smith")
        
        // 2. Merge S2 into S1
        let sourceKey = "S2"
        let targetKey = "S1"
        for seg in segments where seg.speakerKey == sourceKey {
            seg.speakerKey = targetKey
        }
        speakers.removeAll(where: { $0.key == sourceKey })
        
        #expect(speakers.count == 1)
        #expect(speakers[0].key == "S1")
        #expect(segments.allSatisfy { $0.speakerKey == "S1" })
    }
}
