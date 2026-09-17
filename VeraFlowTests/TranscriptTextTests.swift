import Foundation
import SwiftUI
import Testing
@testable import VeraFlow

@MainActor
struct TranscriptTextTests {
    private let words = [
        TimedWord(text: "Call", start: 0, end: 0.3),
        TimedWord(text: "the", start: 0.4, end: 0.5),
        TimedWord(text: "county", start: 0.6, end: 1.0),
    ]

    @Test("Search is case-insensitive and ignores a blank query")
    func search() {
        let texts = ["Call the county", "Pour the footer", "Permit first"]
        #expect(TranscriptText.matches(query: "THE", in: texts) == [0, 1])
        #expect(TranscriptText.matches(query: "  permit ", in: texts) == [2])
        #expect(TranscriptText.matches(query: "   ", in: texts).isEmpty)
        #expect(TranscriptText.matches(query: "nothing", in: texts).isEmpty)
    }

    @Test("Highlighted text keeps the exact words and marks only the current one")
    func highlight() {
        let text = "Call the county"
        let highlighted = TranscriptText.attributed(text: text, words: words, highlightedWord: 2)
        #expect(String(highlighted.characters) == text)
        let marked = highlighted.runs.filter { $0.backgroundColor != nil }
        #expect(marked.count == 1)
        #expect(String(highlighted[marked[0].range].characters) == "county")

        let plain = TranscriptText.attributed(text: text, words: words, highlightedWord: nil)
        #expect(plain.runs.allSatisfy { $0.backgroundColor == nil })
    }

    @Test("An edited paragraph shows its text without word highlight")
    func editedParagraph() {
        let edited = TranscriptText.attributed(text: "Call the county office", words: words, highlightedWord: 1)
        #expect(String(edited.characters) == "Call the county office")
        #expect(edited.runs.allSatisfy { $0.backgroundColor == nil })
        #expect(!TranscriptText.wordsMatch(text: "Call the county office", words: words))
        #expect(TranscriptText.wordsMatch(text: "Call the county", words: words))
    }

    @Test("Commit trims, keeps the original, ignores blanks and no-ops; revert restores")
    func commitAndRevert() {
        let segment = TranscriptSegment(index: 0, start: 0, end: 1, text: "Call the county", words: words)
        #expect(!TranscriptText.commit("   ", to: segment))
        #expect(!TranscriptText.commit("Call the county", to: segment))
        #expect(segment.text == "Call the county")
        #expect(!segment.isEdited)

        #expect(TranscriptText.commit("  Call the county office\n", to: segment))
        #expect(segment.text == "Call the county office")
        #expect(segment.originalText == "Call the county")
        #expect(segment.isEdited)

        TranscriptText.revert(segment)
        #expect(segment.text == "Call the county")
        #expect(!segment.isEdited)
    }
}
