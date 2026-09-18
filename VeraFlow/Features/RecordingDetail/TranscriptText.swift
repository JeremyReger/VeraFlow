import Foundation
import SwiftUI

/// Pure helpers behind the Transcript tab: search, the highlighted paragraph text, and edits.
enum TranscriptText {
    /// Indices of paragraphs whose text contains `query` (case- and diacritic-insensitive).
    /// An empty or whitespace query matches nothing, so the list shows no search state.
    static func matches(query: String, in texts: [String]) -> [Int] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return texts.indices.filter { index in
            texts[index].range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    /// True when `text` is still exactly the words joined by spaces, so word indices line up.
    static func wordsMatch(text: String, words: [TimedWord]) -> Bool {
        !words.isEmpty && words.map(\.text).joined(separator: " ") == text
    }

    /// Paragraph text with the word at `highlightedWord` marked; the plain text when the words
    /// no longer line up (edited paragraph) or nothing is highlighted.
    static func attributed(text: String, words: [TimedWord], highlightedWord: Int?) -> AttributedString {
        guard let highlightedWord, wordsMatch(text: text, words: words), words.indices.contains(highlightedWord) else {
            return AttributedString(text)
        }
        var result = AttributedString()
        for (index, word) in words.enumerated() {
            var piece = AttributedString(word.text)
            if index == highlightedWord {
                piece.backgroundColor = VFColor.accent.opacity(0.28)
                piece.underlineStyle = .single
            }
            result += piece
            if index < words.count - 1 {
                result += AttributedString(" ")
            }
        }
        return result
    }

    /// Applies an edit: trims whitespace, keeps `originalText` untouched, and ignores no-op edits.
    /// Returns true if the segment changed.
    @discardableResult
    static func commit(_ draft: String, to segment: TranscriptSegment) -> Bool {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != segment.text else { return false }
        segment.text = trimmed
        return true
    }

    /// Puts the transcribed text back.
    static func revert(_ segment: TranscriptSegment) {
        segment.text = segment.originalText
    }
}
