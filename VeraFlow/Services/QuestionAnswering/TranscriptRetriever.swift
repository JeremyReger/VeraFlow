import Foundation

/// One transcript paragraph as the retriever sees it.
struct RetrievablePassage: Equatable, Sendable {
    var index: Int
    var start: TimeInterval
    var end: TimeInterval
    var speakerKey: String?
    var speakerDisplayName: String
    var text: String
}

/// Picks the paragraphs most likely to answer a question (v1.1 plan item 11). BM25 over
/// lowercased, stopword-stripped tokens, with the speaker's name as tokens too so "what did
/// Dave say about…" leans towards Dave's lines. Pure, no model involved.
enum TranscriptRetriever {
    static let stopwords: Set<String> = ActionItemPostProcessor.stopwords.union([
        "what", "when", "where", "who", "why", "how", "did", "do", "does", "was", "were", "are",
        "say", "said", "about", "tell", "me", "the", "of", "any", "there", "they", "he", "she",
        "his", "her", "their", "them", "us", "you", "your", "can", "could", "would", "get", "got",
        "have", "has", "had", "been", "being", "or", "if", "so", "then", "than", "as", "from",
        "into", "which", "mention", "mentioned", "talk", "talked", "discuss", "discussed",
    ])

    /// Lowercased word tokens without stopwords or punctuation.
    static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" })
            .map { String($0).replacingOccurrences(of: "'", with: "") }
            .filter { $0.count > 1 && !stopwords.contains($0) }
    }

    /// BM25 score per passage for the question; zero when nothing overlaps.
    static func scores(question: String, passages: [RetrievablePassage], k1: Double = 1.2, b: Double = 0.75) -> [Double] {
        let query = tokens(question)
        guard !query.isEmpty, !passages.isEmpty else { return Array(repeating: 0, count: passages.count) }
        let documents = passages.map { tokens($0.speakerDisplayName + " " + $0.text) }
        let averageLength = max(1, Double(documents.reduce(0) { $0 + $1.count }) / Double(documents.count))
        var documentFrequency: [String: Int] = [:]
        for document in documents {
            for term in Set(document) {
                documentFrequency[term, default: 0] += 1
            }
        }
        let total = Double(documents.count)
        return documents.map { document in
            guard !document.isEmpty else { return 0 }
            var counts: [String: Int] = [:]
            for term in document { counts[term, default: 0] += 1 }
            let length = Double(document.count)
            var score = 0.0
            for term in Set(query) {
                guard let frequency = counts[term] else { continue }
                let n = Double(documentFrequency[term] ?? 0)
                let idf = log(1 + (total - n + 0.5) / (n + 0.5))
                let tf = Double(frequency)
                score += idf * (tf * (k1 + 1)) / (tf + k1 * (1 - b + b * length / averageLength))
            }
            return score
        }
    }

    /// The passages to hand the model: the best-scoring ones with one neighbour each side, in
    /// transcript order, as many as fit `budgetTokens` (counted on the formatted line). A
    /// question that matches nothing returns nothing, so the answer is "not found" without a
    /// model call.
    static func select(
        question: String,
        passages: [RetrievablePassage],
        budgetTokens: Int,
        maximumSeeds: Int = 6,
        tokenCount: (String) -> Int = TranscriptChunker.estimateTokens
    ) -> [RetrievablePassage] {
        let scored = scores(question: question, passages: passages)
        let ranked = passages.indices
            .filter { scored[$0] > 0 }
            .sorted { scored[$0] == scored[$1] ? $0 < $1 : scored[$0] > scored[$1] }
        guard !ranked.isEmpty else { return [] }

        var chosen = Set<Int>()
        var used = 0
        func cost(_ index: Int) -> Int {
            let passage = passages[index]
            return tokenCount(TranscriptChunker.format(TranscriptLine(start: passage.start, speakerKey: passage.speakerKey, speakerDisplayName: passage.speakerDisplayName, text: passage.text))) + 1
        }
        func add(_ index: Int) -> Bool {
            guard passages.indices.contains(index), !chosen.contains(index) else { return true }
            let extra = cost(index)
            guard used + extra <= budgetTokens else { return false }
            chosen.insert(index)
            used += extra
            return true
        }
        for index in ranked.prefix(maximumSeeds) {
            guard add(index) else { break }
            _ = add(index - 1)
            _ = add(index + 1)
        }
        return chosen.sorted().map { passages[$0] }
    }

    /// The transcript lines for the prompt, in order.
    static func lines(for passages: [RetrievablePassage]) -> [TranscriptLine] {
        passages.map { TranscriptLine(start: $0.start, speakerKey: $0.speakerKey, speakerDisplayName: $0.speakerDisplayName, text: $0.text) }
    }
}
