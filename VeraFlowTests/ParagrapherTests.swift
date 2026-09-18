import Foundation
import Testing
@testable import VeraFlow

struct ParagrapherTests {
    /// Words 0.3 s long, spoken back to back with the given gaps before each.
    private func words(_ texts: [String], gaps: [TimeInterval]? = nil, wordLength: TimeInterval = 0.3) -> [TimedWord] {
        var time: TimeInterval = 0
        return texts.enumerated().map { index, text in
            if index > 0 { time += gaps?[index] ?? 0.1 }
            defer { time += wordLength }
            return TimedWord(text: text, start: time, end: time + wordLength)
        }
    }

    @Test("A gap longer than 1.2 s starts a new paragraph; a shorter one does not")
    func gapRule() {
        let short = words(["one", "two", "three"], gaps: [0, 1.2, 0.1])
        #expect(Paragrapher.segments(from: short).count == 1)

        let long = words(["one", "two", "three"], gaps: [0, 1.21, 0.1])
        let segments = Paragrapher.segments(from: long)
        #expect(segments.map(\.text) == ["one", "two three"])
        #expect(segments[0].start == 0)
        #expect(segments[0].end == 0.3)
        #expect(segments[1].start == long[1].start)
    }

    @Test("A sentence end breaks only once the paragraph is past 25 words")
    func sentenceRule() {
        // 20 words then "done." → no break yet; 30 words then "done." → break.
        var texts = Array(repeating: "w", count: 20) + ["done."] + Array(repeating: "w", count: 5) + ["end."]
        var segments = Paragrapher.segments(from: words(texts))
        #expect(segments.count == 1, "26 words total but the first sentence ended at word 21, under the limit")

        texts = Array(repeating: "w", count: 30) + ["done."] + ["after"]
        segments = Paragrapher.segments(from: words(texts))
        #expect(segments.map { $0.words.count } == [31, 1])
    }

    @Test("Paragraphs never run longer than 45 s")
    func durationRule() {
        // 200 words at 0.4 s pitch = 80 s of speech with no sentence ends and no gaps.
        let many = words(Array(repeating: "w", count: 200), gaps: Array(repeating: 0.1, count: 200))
        let segments = Paragrapher.segments(from: many)
        #expect(segments.count >= 2)
        for segment in segments {
            #expect(segment.end - segment.start <= 45)
        }
        #expect(segments.flatMap(\.words) == many, "no word is dropped or reordered")
    }

    @Test("Sentence detection ignores closing quotes and brackets")
    func sentenceEnd() {
        #expect(Paragrapher.endsSentence("done."))
        #expect(Paragrapher.endsSentence("really?\""))
        #expect(Paragrapher.endsSentence("wow!)"))
        #expect(!Paragrapher.endsSentence("Mr."))
        #expect(!Paragrapher.endsSentence("ft."))
        #expect(Paragrapher.endsSentence("Friday."))
        #expect(!Paragrapher.endsSentence("hello"))
        #expect(!Paragrapher.endsSentence(""))
    }

    @Test("Empty input gives no paragraphs; one word gives one")
    func edges() {
        #expect(Paragrapher.segments(from: []).isEmpty)
        let one = Paragrapher.segments(from: [TimedWord(text: "hi", start: 1, end: 1.4)])
        #expect(one == [ProvisionalSegment(start: 1, end: 1.4, words: [TimedWord(text: "hi", start: 1, end: 1.4)])])
        #expect(one[0].text == "hi")
    }
}
