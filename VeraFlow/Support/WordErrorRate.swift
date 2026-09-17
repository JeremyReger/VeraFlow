import Foundation

/// Word error rate: (substitutions + deletions + insertions) / reference words, on normalized
/// tokens (lowercased, punctuation stripped). Used by the engine benchmark (SPEC §9.4, §16 M3).
enum WordErrorRate {
    struct Score: Equatable, Sendable {
        var substitutions: Int
        var deletions: Int
        var insertions: Int
        var referenceCount: Int

        var errors: Int { substitutions + deletions + insertions }
        /// 0 is perfect. Can exceed 1 when the hypothesis is much longer than the reference.
        var rate: Double { referenceCount == 0 ? (errors == 0 ? 0 : 1) : Double(errors) / Double(referenceCount) }
    }

    static func normalize(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map { token in
                String(token.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "'" })
            }
            .filter { !$0.isEmpty }
    }

    static func score(reference: String, hypothesis: String) -> Score {
        score(reference: normalize(reference), hypothesis: normalize(hypothesis))
    }

    /// Levenshtein alignment with backtrace so the three error kinds are counted separately.
    static func score(reference: [String], hypothesis: [String]) -> Score {
        let n = reference.count
        let m = hypothesis.count
        var cost = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 0...n { cost[i][0] = i }
        for j in 0...m { cost[0][j] = j }
        if n > 0, m > 0 {
            for i in 1...n {
                for j in 1...m {
                    let same = reference[i - 1] == hypothesis[j - 1]
                    cost[i][j] = min(
                        cost[i - 1][j - 1] + (same ? 0 : 1),
                        cost[i - 1][j] + 1,
                        cost[i][j - 1] + 1
                    )
                }
            }
        }
        var i = n
        var j = m
        var result = Score(substitutions: 0, deletions: 0, insertions: 0, referenceCount: n)
        while i > 0 || j > 0 {
            if i > 0, j > 0, reference[i - 1] == hypothesis[j - 1], cost[i][j] == cost[i - 1][j - 1] {
                i -= 1
                j -= 1
            } else if i > 0, j > 0, cost[i][j] == cost[i - 1][j - 1] + 1 {
                result.substitutions += 1
                i -= 1
                j -= 1
            } else if i > 0, cost[i][j] == cost[i - 1][j] + 1 {
                result.deletions += 1
                i -= 1
            } else {
                result.insertions += 1
                j -= 1
            }
        }
        return result
    }
}
