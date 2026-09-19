import Foundation
import Testing
@testable import VeraFlow

struct TranscriptMarkersTests {
    @Test("A mark sits before the first paragraph that starts after it; trailing marks go last")
    func placements() {
        let starts: [TimeInterval] = [0, 10, 25]
        let placements = TranscriptMarkers.placements(markTimes: [12, 30, 3, 10], segmentStarts: starts)
        #expect(placements[1] == [2], "3 s goes before the paragraph at 10 s")
        #expect(placements[2] == [3, 0], "10 s and 12 s go before the paragraph at 25 s, in time order")
        #expect(placements[3] == [1], "30 s goes after the last paragraph")
        #expect(placements[0] == nil)
        #expect(TranscriptMarkers.placements(markTimes: [], segmentStarts: starts).isEmpty)
        #expect(TranscriptMarkers.placements(markTimes: [5], segmentStarts: []) == [0: [0]])
    }
}
