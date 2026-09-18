import Foundation
import Testing
@testable import VeraFlow

struct TalkTimeTests {
    @Test("Talk time sums per speaker, skips unlabelled speech, and sorts longest first")
    func shares() {
        let shares = TalkTime.shares(segments: [
            (speakerKey: "S1", start: 0, end: 10),
            (speakerKey: "S2", start: 10, end: 40),
            (speakerKey: nil, start: 40, end: 100),
            (speakerKey: "S1", start: 100, end: 120),
            (speakerKey: "S3", start: 130, end: 125),   // bad range counts as nothing
        ])
        #expect(shares.map(\.speakerKey) == ["S1", "S2", "S3"])
        #expect(shares[0].seconds == 30)
        #expect(shares[1].seconds == 30)
        #expect(shares[2].seconds == 0)
        #expect(shares[0].fraction == 0.5)
        #expect(shares[1].fraction == 0.5)
        #expect(shares[2].fraction == 0)
    }

    @Test("No labelled speech gives no rows")
    func empty() {
        #expect(TalkTime.shares(segments: []).isEmpty)
        #expect(TalkTime.shares(segments: [(speakerKey: nil, start: 0, end: 5)]).isEmpty)
    }
}
