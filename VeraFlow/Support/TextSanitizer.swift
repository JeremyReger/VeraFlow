import Foundation

/// Strips links and markdown from model-written text before it becomes a reminder title or an
/// email body (security review S-14). Transcript text reaches the model verbatim, so a speaker
/// could dictate a link; nothing the model writes is followed automatically, but the text
/// shouldn't carry it into Reminders or Mail either.
enum TextSanitizer {
    private static let linkPattern = try! NSRegularExpression(
        pattern: #"\[([^\]]*)\]\([^)]*\)|(?:https?://|www\.)\S+"#,
        options: [.caseInsensitive]
    )
    private static let markupCharacters = CharacterSet(charactersIn: "*_`#>")

    /// Markdown links keep their text; bare URLs are removed; emphasis and heading markers are
    /// dropped; whitespace is collapsed.
    static func stripLinksAndMarkup(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        var result = linkPattern.stringByReplacingMatches(in: text, range: range, withTemplate: "$1")
        result = String(result.unicodeScalars.filter { !markupCharacters.contains($0) })
        return result
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Same as `stripLinksAndMarkup` but keeps line breaks (email bodies).
    static func stripLinksAndMarkupKeepingLines(_ text: String) -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { stripLinksAndMarkup(String($0)) }
            .joined(separator: "\n")
    }
}
