import Foundation
import Testing
@testable import VeraFlow

struct AudioLevelTests {
    @Test("Silence is 0 and full scale is 1")
    func endpoints() {
        #expect(AudioLevel.normalized(peak: 0) == 0)
        #expect(AudioLevel.normalized(peak: 1) == 1)
        #expect(AudioLevel.normalized(peak: 2) == 1)
    }

    @Test("Quieter peaks map lower on a decibel scale")
    func monotonic() {
        let loud = AudioLevel.normalized(peak: 0.5)
        let quiet = AudioLevel.normalized(peak: 0.05)
        let silent = AudioLevel.normalized(peak: 0.0005)
        #expect(loud > quiet)
        #expect(quiet > silent)
        #expect(silent >= 0)
        // -6 dB on a 60 dB scale is 90%.
        #expect(abs(loud - 0.9) < 0.01)
    }
}
