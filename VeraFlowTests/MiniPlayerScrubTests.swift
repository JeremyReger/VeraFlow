import Foundation
import Testing
@testable import VeraFlow

/// Drag-to-seek on the mini player (Jeremy, 2026-09-19). The gesture itself needs a running view,
/// so what's tested here is the arithmetic it feeds: where a click lands, and where the thumb is
/// drawn for it.
struct MiniPlayerScrubTests {
    @Test("A click maps to its fraction of the track")
    func fractionAcrossTrack() {
        #expect(VFMiniPlayer.fraction(0, width: 200) == 0)
        #expect(VFMiniPlayer.fraction(100, width: 200) == 0.5)
        #expect(VFMiniPlayer.fraction(200, width: 200) == 1)
    }

    @Test("A drag past either end clamps instead of running off")
    func fractionClamps() {
        #expect(VFMiniPlayer.fraction(-40, width: 200) == 0, "dragging left of the bar seeks to the start")
        #expect(VFMiniPlayer.fraction(320, width: 200) == 1, "dragging past the end seeks to the end")
    }

    @Test("A zero-width track can't divide, and reports the start")
    func fractionZeroWidth() {
        #expect(VFMiniPlayer.fraction(50, width: 0) == 0)
    }

    @Test("The thumb is centred on the playhead and stays fully on the track at both ends")
    func thumbStaysOnTrack() {
        let width: CGFloat = 200
        let travel = width - 11
        #expect(VFMiniPlayer.thumbX(progress: 0, width: width) == 0)
        #expect(VFMiniPlayer.thumbX(progress: 1, width: width) == travel)
        #expect(VFMiniPlayer.thumbX(progress: 0.5, width: width) == 94.5)
    }

    @Test("A track narrower than the thumb pins it at the left rather than going negative")
    func thumbOnTinyTrack() {
        #expect(VFMiniPlayer.thumbX(progress: 1, width: 4) == 0)
    }
}
