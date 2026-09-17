import Foundation
import Testing
@testable import VeraFlow

/// SPEC §10.2 on synthetic word/turn fixtures. Cases 1–6 were ported from the Antigravity
/// branch's `TranscriptAlignerTests` (docs/reviews/2026-09-17-antigravity-review.md).
struct TranscriptAlignerTests {
    private let aligner = LiveTranscriptAligner()

    @Test("Alternating two-speaker dialogue gives one paragraph per turn with keys by first appearance")
    func alternatingDialogue() {
        let words = [
            TimedWord(text: "Hello", start: 0.0, end: 0.5),
            TimedWord(text: "Alice.", start: 0.6, end: 1.0),
            TimedWord(text: "Hi", start: 1.5, end: 1.8),
            TimedWord(text: "Bob.", start: 1.9, end: 2.3),
            TimedWord(text: "Good", start: 2.8, end: 3.1),
            TimedWord(text: "morning.", start: 3.2, end: 3.6),
        ]
        let turns = [
            SpeakerTurn(speakerID: "RAW_A", start: 0.0, end: 1.2),
            SpeakerTurn(speakerID: "RAW_B", start: 1.4, end: 2.5),
            SpeakerTurn(speakerID: "RAW_A", start: 2.7, end: 4.0),
        ]
        let segments = aligner.align(words: words, turns: turns)
        #expect(segments.map(\.speakerKey) == ["S1", "S2", "S1"])
        #expect(segments.map(\.text) == ["Hello Alice.", "Hi Bob.", "Good morning."])
        #expect(segments[0].start == 0.0)
        #expect(segments[2].end == 3.6)
    }

    @Test("A word straddling two turns goes to the larger overlap")
    func largestOverlap() {
        let words = [TimedWord(text: "Straddler", start: 1.0, end: 1.5)]
        let turns = [
            SpeakerTurn(speakerID: "RAW_A", start: 0.0, end: 1.2),
            SpeakerTurn(speakerID: "RAW_B", start: 1.2, end: 2.5),
        ]
        // Overlap with B is 0.3 s, with A 0.2 s, so B is the first (and only) speaker seen.
        #expect(LiveTranscriptAligner.speakerKeys(for: words, turns: turns) == ["S1"])
        #expect(aligner.align(words: words, turns: turns).first?.speakerKey == "S1")
    }

    @Test("A word in a gap takes the nearest turn within half a second")
    func nearestTurn() {
        let turns = [
            SpeakerTurn(speakerID: "RAW_A", start: 0.0, end: 1.0),
            SpeakerTurn(speakerID: "RAW_B", start: 2.0, end: 3.0),
        ]
        let words = [
            TimedWord(text: "NearA", start: 1.1, end: 1.3),
            TimedWord(text: "NearB", start: 1.7, end: 1.9),
        ]
        let segments = aligner.align(words: words, turns: turns)
        #expect(segments.map(\.text) == ["NearA", "NearB"])
        #expect(segments.map(\.speakerKey) == ["S1", "S2"])
    }

    @Test("A word far from every turn keeps the previous word's speaker")
    func previousSpeakerFallback() {
        let turns = [SpeakerTurn(speakerID: "RAW_A", start: 0.0, end: 1.0)]
        let words = [
            TimedWord(text: "In", start: 0.1, end: 0.3),
            TimedWord(text: "silence", start: 5.0, end: 5.4),
        ]
        #expect(LiveTranscriptAligner.speakerKeys(for: words, turns: turns) == ["S1", "S1"])
    }

    @Test("A run of fewer than three words between the same speaker is smoothed away")
    func smoothing() {
        let words = [
            TimedWord(text: "One", start: 0.0, end: 0.3),
            TimedWord(text: "two", start: 0.4, end: 0.7),
            TimedWord(text: "three.", start: 0.8, end: 1.1),
            TimedWord(text: "brief", start: 1.2, end: 1.4),
            TimedWord(text: "cough", start: 1.5, end: 1.7),
            TimedWord(text: "four", start: 1.8, end: 2.1),
            TimedWord(text: "five", start: 2.2, end: 2.5),
            TimedWord(text: "six.", start: 2.6, end: 2.9),
        ]
        let turns = [
            SpeakerTurn(speakerID: "RAW_A", start: 0.0, end: 1.15),
            SpeakerTurn(speakerID: "RAW_B", start: 1.16, end: 1.75),
            SpeakerTurn(speakerID: "RAW_A", start: 1.76, end: 3.0),
        ]
        let segments = aligner.align(words: words, turns: turns)
        #expect(segments.count == 1)
        #expect(segments[0].speakerKey == "S1")
        #expect(segments[0].words.count == 8)
        #expect(LiveTranscriptAligner.smoothed(["a", "a", "b", "a", "a"]) == ["a", "a", "a", "a", "a"])
        #expect(LiveTranscriptAligner.smoothed(["a", "b", "b", "b", "a"]) == ["a", "b", "b", "b", "a"])
        #expect(LiveTranscriptAligner.smoothed(["b", "a", "a"]) == ["b", "a", "a"], "runs at the edges are kept")
    }

    @Test("Runs of three or more words are kept")
    func threeWordRunKept() {
        let words = [
            TimedWord(text: "One", start: 0.0, end: 0.3),
            TimedWord(text: "two", start: 0.4, end: 0.7),
            TimedWord(text: "three.", start: 0.8, end: 1.1),
            TimedWord(text: "now", start: 1.2, end: 1.4),
            TimedWord(text: "three", start: 1.5, end: 1.7),
            TimedWord(text: "words.", start: 1.8, end: 2.0),
            TimedWord(text: "four", start: 2.1, end: 2.4),
            TimedWord(text: "five", start: 2.5, end: 2.8),
            TimedWord(text: "six.", start: 2.9, end: 3.2),
        ]
        let turns = [
            SpeakerTurn(speakerID: "RAW_A", start: 0.0, end: 1.15),
            SpeakerTurn(speakerID: "RAW_B", start: 1.16, end: 2.05),
            SpeakerTurn(speakerID: "RAW_A", start: 2.06, end: 3.5),
        ]
        let segments = aligner.align(words: words, turns: turns)
        #expect(segments.map(\.speakerKey) == ["S1", "S2", "S1"])
        #expect(segments[1].words.count == 3)
    }

    @Test("Keys follow chronological first appearance, not the diarizer's IDs")
    func keyOrder() {
        let words = [
            TimedWord(text: "First", start: 0.0, end: 0.5),
            TimedWord(text: "Second", start: 1.0, end: 1.5),
            TimedWord(text: "Third", start: 2.0, end: 2.5),
        ]
        let turns = [
            SpeakerTurn(speakerID: "SPEAKER_ZEBRA", start: 0.0, end: 0.8),
            SpeakerTurn(speakerID: "SPEAKER_ALPHA", start: 0.9, end: 1.8),
            SpeakerTurn(speakerID: "SPEAKER_ZEBRA", start: 1.9, end: 2.8),
        ]
        #expect(aligner.align(words: words, turns: turns).map(\.speakerKey) == ["S1", "S2", "S1"])
    }

    @Test("Paragraph rules still apply inside one speaker's run; no turns means plain paragraphs")
    func paragraphRulesWithinSpeaker() {
        var time: TimeInterval = 0
        var words: [TimedWord] = []
        for index in 0..<6 {
            words.append(TimedWord(text: "w\(index)", start: time, end: time + 0.3))
            time += index == 2 ? 2.0 : 0.4 // a 1.7 s silence after the third word
        }
        let turns = [SpeakerTurn(speakerID: "A", start: 0, end: 10)]
        let labeled = aligner.align(words: words, turns: turns)
        #expect(labeled.map { $0.words.count } == [3, 3])
        #expect(labeled.map(\.speakerKey) == ["S1", "S1"])

        let plain = aligner.align(words: words, turns: [])
        #expect(plain.map { $0.words.count } == [3, 3])
        #expect(plain.allSatisfy { $0.speakerKey == nil })
        #expect(aligner.align(words: [], turns: turns).isEmpty)
    }

    @Test("Existing paragraphs are labeled by majority vote without being re-split")
    func labelExistingSegments() {
        let first = (0..<4).map { TimedWord(text: "a\($0)", start: Double($0) * 0.5, end: Double($0) * 0.5 + 0.4) } // 0–1.9
        let second = (0..<4).map { TimedWord(text: "b\($0)", start: 2 + Double($0) * 0.5, end: 2 + Double($0) * 0.5 + 0.4) } // 2–3.9
        let turns = [
            SpeakerTurn(speakerID: "X", start: 0, end: 1.6),   // covers a0–a2 (3 of 4)
            SpeakerTurn(speakerID: "Y", start: 1.6, end: 4.0), // a3 and all of b
        ]
        let keys = aligner.speakerKeys(forSegments: [first, second], turns: turns)
        #expect(keys == ["S1", "S2"])
        #expect(aligner.speakerKeys(forSegments: [first, second], turns: []) == [nil, nil])
        #expect(aligner.speakerKeys(forSegments: [], turns: turns).isEmpty)
    }
}
