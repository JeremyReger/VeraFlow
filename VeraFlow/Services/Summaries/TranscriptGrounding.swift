import Foundation

/// Drops what the transcript doesn't support.
///
/// CLAUDE.md's guardrail has no exceptions: the model never invents names, numbers, dates, prices
/// or measurements. Until now that was only ever *asked for*, in a prompt and in the schema's
/// descriptions. On 2026-09-20 a 35-second, 117-word recording came back from the walkthrough
/// template with ten rooms and twenty-odd measurements — a whole house that was never walked — and
/// one of those answers was saved. A request is not a guarantee. This is the guarantee, and it
/// lives in Swift for the same reason due dates do.
///
/// The rule follows the guardrail's own wording rather than trying to judge truth:
///
/// - **Anything carrying a number** is kept only when every number in it was spoken. This is the
///   strict one, and it covers measurements, quantities and prices. "12 ft 4 in" survives only if
///   12 and 4 were both said.
/// - **Anything naming a thing** — an area, a material, a due-date phrase, an owner — is kept only
///   when the transcript mentions it. A room nobody walked into can't be a room.
/// - **Prose that paraphrases** — the overview, a task, an issue found — is left alone, because
///   summarising is the job, unless it carries a number it shouldn't.
///
/// The overview is deliberately exempt from removal: dropping it leaves a summary with nothing to
/// read. Its numbers are still checked, and an unsupported one is a flag, not a deletion — see
/// `unsupportedOverviewNumbers`. DECISIONS.md 2026-09-20 records that as the open edge.
enum TranscriptGrounding {

    // MARK: - Index

    /// The transcript in the one form every check compares against.
    struct Index: Sendable {
        /// Folded to lowercase words and digits, with spoken number words written as digits so
        /// "twelve foot four" can ground "12 ft 4 in". Padded with spaces at both ends, so a
        /// whole-word search is a plain substring search.
        let haystack: String
        /// Every number the transcript spoke, as digits.
        let numbers: Set<String>

        /// True when every number in `text` was spoken. Text with no numbers passes: this check
        /// is about invented figures, not about vocabulary.
        func numbersAreSpoken(in text: String) -> Bool {
            TranscriptGrounding.numbers(in: text).isSubset(of: numbers)
        }

        /// True when the whole phrase appears in the transcript, word for word after folding.
        func mentions(_ phrase: String) -> Bool {
            let folded = TranscriptGrounding.fold(phrase)
            guard !folded.isEmpty else { return false }
            return haystack.contains(" \(folded) ")
        }

        /// True when the phrase shares a telling word with the transcript.
        ///
        /// Names get this looser test on purpose. The model writes "Master bath" for a transcript
        /// that said "master bathroom", and a verbatim match would throw away a real area. What it
        /// will not do is let "Storage room" through on the strength of "room", so words that say
        /// nothing about *which* thing this is don't count as a match.
        func namesSomethingSpoken(_ name: String) -> Bool {
            let words = TranscriptGrounding.fold(name).split(separator: " ").map(String.init)
            let telling = words.filter { $0.count >= 3 && !TranscriptGrounding.genericWords.contains($0) }
            // A name made only of generic words has nothing to check, so it has to match whole.
            guard !telling.isEmpty else { return mentions(name) }
            return telling.contains { haystack.contains(" \($0) ") }
        }
    }

    /// Built from the transcript paragraphs plus the speaker names, because an owner is usually a
    /// speaker label that the paragraph text itself never contains.
    static func index(segments: [(start: TimeInterval, text: String)], speakers: [String] = []) -> Index {
        index(transcript: (segments.map { $0.text } + speakers).joined(separator: "\n"))
    }

    static func index(transcript: String) -> Index {
        let folded = fold(transcript)
        // Numbers are read off the raw transcript, not the folded one: folding turns every
        // non-alphanumeric into a space, which would split "12.5" into a 12 and a 5 and ground a
        // measurement nobody spoke. The folded text is then read a second time for numbers that
        // were said as words.
        var spoken = numbers(in: transcript)
        spoken.formUnion(numbers(in: expandingNumberWords(in: folded)))
        return Index(haystack: " \(folded) ", numbers: spoken)
    }

    // MARK: - Grounding

    static func grounded(_ payload: SummaryPayload, in index: Index) -> SummaryPayload {
        switch payload {
        case .general(var summary):
            summary.keyPoints = numbered(summary.keyPoints, index)
            summary.topics = summary.topics.map { topic in
                KeyPointTopic(title: topic.title, points: numbered(topic.points, index), start: topic.start)
            }
            summary.decisions = numbered(summary.decisions, index)
            summary.openQuestions = numbered(summary.openQuestions, index)
            summary.actionItems = grounded(summary.actionItems, index)
            return .general(summary)

        case .client(var summary):
            summary.clientGoals = numbered(summary.clientGoals, index)
            summary.concerns = numbered(summary.concerns, index)
            summary.decisions = numbered(summary.decisions, index)
            summary.openQuestions = numbered(summary.openQuestions, index)
            summary.topics = summary.topics.map { topic in
                KeyPointTopic(title: topic.title, points: numbered(topic.points, index), start: topic.start)
            }
            if !summary.nextMeeting.isEmpty, !index.mentions(summary.nextMeeting) { summary.nextMeeting = "" }
            summary.actionItems = grounded(summary.actionItems, index)
            return .client(summary)

        case .walkthrough(var summary):
            // An address nobody read out is the clearest case of all: "123 Main St." appeared in
            // an answer to a transcript that never says it.
            if !summary.location.isEmpty, !index.mentions(summary.location) { summary.location = "" }
            summary.areas = summary.areas.compactMap { area in
                guard index.namesSomethingSpoken(area.name) else { return nil }
                return WorkArea(
                    name: area.name,
                    tasks: numbered(area.tasks, index),
                    measurements: area.measurements.filter { index.numbersAreSpoken(in: $0.value) },
                    materials: area.materials.filter {
                        index.namesSomethingSpoken($0.name) && index.numbersAreSpoken(in: $0.quantity)
                    },
                    start: area.start
                )
            }
            summary.customerRequests = numbered(summary.customerRequests, index)
            summary.issuesFound = numbered(summary.issuesFound, index)
            summary.quoteNotes = numbered(summary.quoteNotes, index)
            summary.actionItems = grounded(summary.actionItems, index)
            return .walkthrough(summary)
        }
    }

    /// Numbers in the overview that were never spoken. Nothing is removed for these — the overview
    /// is the one field a summary can't do without — but they're worth logging.
    static func unsupportedOverviewNumbers(_ payload: SummaryPayload, in index: Index) -> Set<String> {
        numbers(in: payload.overview).subtracting(index.numbers)
    }

    // MARK: - Pieces

    /// An owner or a due date the transcript never says is cleared rather than dropping the task:
    /// the task itself is usually real even when the model has filled in who and when.
    static func grounded(_ items: [ActionItem], _ index: Index) -> [ActionItem] {
        items.compactMap { item in
            guard index.numbersAreSpoken(in: item.task) else { return nil }
            var result = item
            if !result.owner.isEmpty, !index.mentions(result.owner) {
                result.owner = ""
                result.ownerSpeakerKey = nil
            }
            if !result.dueText.isEmpty, !index.mentions(result.dueText) {
                result.dueText = ""
                result.dueDate = nil
            }
            return result
        }
    }

    private static func numbered(_ lines: [String], _ index: Index) -> [String] {
        lines.filter { index.numbersAreSpoken(in: $0) }
    }

    // MARK: - Text

    /// Lowercase, accent-blind, and everything that isn't a letter or a digit becomes a space, so
    /// punctuation and casing can't decide whether a measurement survives.
    static func fold(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let characters = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(characters).split(separator: " ").joined(separator: " ")
    }

    /// Every number in the text, as digits, with leading zeros and a trailing ".0" normalised away
    /// so "04" and "4.0" both ground "4". Reads the text as given — a decimal point has to survive
    /// to be part of a number.
    static func numbers(in text: String) -> Set<String> {
        var result: Set<String> = []
        var current = ""
        for character in text + " " {
            if character.isNumber || (character == "." && !current.isEmpty) {
                current.append(character)
            } else if !current.isEmpty {
                result.insert(normalize(current))
                current = ""
            }
        }
        return result
    }

    private static func normalize(_ number: String) -> String {
        var value = number
        while value.hasSuffix(".") { value.removeLast() }
        if value.contains(".") {
            while value.hasSuffix("0") { value.removeLast() }
            while value.hasSuffix(".") { value.removeLast() }
        }
        while value.count > 1, value.hasPrefix("0") { value.removeFirst() }
        return value.isEmpty ? "0" : value
    }

    /// Writes spoken numbers as digits. A transcript reads "twelve foot four", and the answer
    /// writes "12 ft 4 in"; without this the real measurement would be thrown away as invented.
    /// A tens word followed by a units word contributes the compound as well as its parts, so
    /// "twenty four" grounds 24, 20 and 4 alike.
    static func expandingNumberWords(in foldedText: String) -> String {
        let words = foldedText.split(separator: " ").map(String.init)
        var result: [String] = []
        var index = 0
        while index < words.count {
            let word = words[index]
            if let tens = tensWords[word] {
                if index + 1 < words.count, let unit = unitWords[words[index + 1]], unit > 0, unit < 10 {
                    result.append(contentsOf: ["\(tens + unit)", "\(tens)", "\(unit)"])
                    index += 2
                    continue
                }
                result.append("\(tens)")
            } else if let unit = unitWords[word] {
                result.append("\(unit)")
            } else {
                result.append(word)
            }
            index += 1
        }
        return result.joined(separator: " ")
    }

    /// Words that say nothing about *which* thing a name refers to, so they can't be the only
    /// reason an area or a material is kept.
    static let genericWords: Set<String> = [
        "the", "and", "area", "areas", "room", "rooms", "space", "spaces", "wall", "walls",
        "floor", "floors", "ceiling", "side", "unit", "units", "main", "new", "old", "general",
    ]

    private static let unitWords: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
        "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13,
        "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18,
        "nineteen": 19, "hundred": 100, "thousand": 1000,
    ]

    private static let tensWords: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]
}
