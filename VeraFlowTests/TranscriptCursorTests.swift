import Foundation
import Testing
@testable import VeraFlow

struct TranscriptCursorTests {
    private let segments: [[TimedWord]] = [
        [TimedWord(text: "one", start: 0.0, end: 0.4), TimedWord(text: "two", start: 0.5, end: 0.9)],
        [TimedWord(text: "three", start: 5.0, end: 5.4), TimedWord(text: "four", start: 5.5, end: 5.9)],
    ]
    private var starts: [TimeInterval] { segments.map { $0[0].start } }

    private func position(at time: TimeInterval, edited: Bool = false) -> TranscriptPosition? {
        TranscriptCursor.position(at: time, starts: starts, words: { segments[$0] }, wordsAreCurrent: { _ in !edited })
    }

    @Test("Binary search finds the last start not after the time")
    func lastIndex() {
        #expect(TranscriptCursor.lastIndex(where: [0, 5, 10], notAfter: -1) == nil)
        #expect(TranscriptCursor.lastIndex(where: [0, 5, 10], notAfter: 0) == 0)
        #expect(TranscriptCursor.lastIndex(where: [0, 5, 10], notAfter: 7) == 1)
        #expect(TranscriptCursor.lastIndex(where: [0, 5, 10], notAfter: 100) == 2)
        #expect(TranscriptCursor.lastIndex(where: [], notAfter: 1) == nil)
    }

    @Test("Highlights the paragraph and the word under the playhead")
    func wordHighlight() {
        #expect(position(at: 0.2) == TranscriptPosition(segmentIndex: 0, wordIndex: 0))
        #expect(position(at: 0.7) == TranscriptPosition(segmentIndex: 0, wordIndex: 1))
        #expect(position(at: 5.6) == TranscriptPosition(segmentIndex: 1, wordIndex: 1))
    }

    @Test("Long pauses inside a paragraph highlight the paragraph only; short gaps keep the word")
    func gaps() {
        #expect(position(at: 3.0) == TranscriptPosition(segmentIndex: 0, wordIndex: nil))
        #expect(position(at: 0.45) == TranscriptPosition(segmentIndex: 0, wordIndex: 0), "within the 0.15 s tolerance after 'one'")
    }

    @Test("Before the first paragraph nothing is highlighted; edited paragraphs highlight whole")
    func edges() {
        #expect(position(at: -1) == nil)
        #expect(position(at: 0.2, edited: true) == TranscriptPosition(segmentIndex: 0, wordIndex: nil))
    }
}
