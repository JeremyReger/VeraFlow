import Foundation
import Testing
@testable import VeraFlow

struct DiskSpacePolicyTests {
    @Test("Thresholds: warn under 500 MB, stop under 100 MB", arguments: [
        (Int64(2_000_000_000), DiskSpacePolicy.Verdict.ok),
        (Int64(500_000_000), .ok),
        (Int64(499_999_999), .warn),
        (Int64(100_000_000), .warn),
        (Int64(99_999_999), .stop),
        (Int64(0), .stop),
    ])
    func thresholds(bytes: Int64, expected: DiskSpacePolicy.Verdict) {
        #expect(DiskSpacePolicy.evaluate(availableBytes: bytes) == expected)
    }

    @Test("Unknown free space never blocks recording")
    func unknownIsOK() {
        #expect(DiskSpacePolicy.evaluate(availableBytes: nil) == .ok)
    }

    @Test("Seconds remaining keeps the stop margin back")
    func secondsRemaining() {
        #expect(DiskSpacePolicy.secondsRemaining(availableBytes: 100_000_000) == 0)
        #expect(DiskSpacePolicy.secondsRemaining(availableBytes: 100_000_000 + 8_000 * 60) == 60)
        #expect(DiskSpacePolicy.secondsRemaining(availableBytes: 0) == 0)
    }
}
