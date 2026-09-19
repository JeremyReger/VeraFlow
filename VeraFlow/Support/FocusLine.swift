import Foundation

/// The per-recording focus (v1.1 plan item 13): one short line the user adds ("pay attention
/// to the budget"). It is quoted inside the instructions *after* the shared rules, so it can
/// steer what the model looks for but not rewrite the rules above it.
enum FocusLine {
    static let maximumLength = 200

    /// One line, no quotes, links or markup, at most `maximumLength` characters.
    static func sanitize(_ raw: String) -> String {
        let oneLine = raw
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        let stripped = TextSanitizer.stripLinksAndMarkup(oneLine)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "\u{201C}", with: "")
            .replacingOccurrences(of: "\u{201D}", with: "")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return String(stripped.prefix(maximumLength)).trimmingCharacters(in: .whitespaces)
    }

    /// The sentence appended to the FINAL instructions, or `nil` when there is no focus.
    static func instruction(for focus: String) -> String? {
        let clean = sanitize(focus)
        guard !clean.isEmpty else { return nil }
        return "The person who recorded this asked you to pay particular attention to: \"\(clean)\". Every rule above still applies; use only what the transcript says."
    }
}
