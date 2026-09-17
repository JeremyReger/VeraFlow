import Testing
@testable import VeraFlow

struct WordErrorRateTests {
    @Test("Identical text scores zero")
    func identical() {
        let score = WordErrorRate.score(reference: "We need the permit.", hypothesis: "we need the permit")
        #expect(score.errors == 0)
        #expect(score.rate == 0)
        #expect(score.referenceCount == 4)
    }

    @Test("Substitutions, deletions, and insertions are counted separately")
    func kinds() {
        // reference: a b c d ; hypothesis: a x c d e  → one substitution (b→x), one insertion (e)
        var score = WordErrorRate.score(reference: ["a", "b", "c", "d"], hypothesis: ["a", "x", "c", "d", "e"])
        #expect(score == WordErrorRate.Score(substitutions: 1, deletions: 0, insertions: 1, referenceCount: 4))
        #expect(score.rate == 0.5)

        // deletion
        score = WordErrorRate.score(reference: ["a", "b", "c"], hypothesis: ["a", "c"])
        #expect(score == WordErrorRate.Score(substitutions: 0, deletions: 1, insertions: 0, referenceCount: 3))
    }

    @Test("Normalization drops case and punctuation but keeps apostrophes")
    func normalization() {
        #expect(WordErrorRate.normalize("Don't pour, the FOOTER!  ok?") == ["don't", "pour", "the", "footer", "ok"])
    }

    @Test("Empty inputs")
    func empties() {
        #expect(WordErrorRate.score(reference: "", hypothesis: "").rate == 0)
        #expect(WordErrorRate.score(reference: "", hypothesis: "extra words").rate == 1)
        #expect(WordErrorRate.score(reference: "two words", hypothesis: "").rate == 1)
    }
}
