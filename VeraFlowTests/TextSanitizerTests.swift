import Foundation
import Testing
@testable import VeraFlow

struct TextSanitizerTests {
    @Test("Bare URLs are removed, markdown links keep their text, emphasis markers are dropped")
    func strips() {
        #expect(TextSanitizer.stripLinksAndMarkup("Send the invoice to https://example.com/pay today") == "Send the invoice to today")
        #expect(TextSanitizer.stripLinksAndMarkup("Read [the brief](http://x.y/z) first") == "Read the brief first")
        #expect(TextSanitizer.stripLinksAndMarkup("**Call** the _county_ at www.county.gov") == "Call the county at")
        #expect(TextSanitizer.stripLinksAndMarkup("`code` and # heading") == "code and heading")
        #expect(TextSanitizer.stripLinksAndMarkup("Plain task with no links.") == "Plain task with no links.")
    }

    @Test("Email bodies keep their line breaks")
    func keepsLines() {
        let body = "Hi Dana,\n\nSee https://evil.example/x for details.\n\nThanks"
        #expect(TextSanitizer.stripLinksAndMarkupKeepingLines(body) == "Hi Dana,\n\nSee for details.\n\nThanks")
    }
}
