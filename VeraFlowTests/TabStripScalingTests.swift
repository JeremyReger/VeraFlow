import SwiftUI
import Testing
@testable import VeraFlow

/// The tab strip at large text sizes (Jeremy, 2026-09-20). On an iPhone at an accessibility size
/// the three tracked-capital labels and the Ask pill were breaking across lines mid-word and
/// truncating: "SU MM A…", "TR AN S…". Whether they fit is now measured by `ViewThatFits`, which
/// needs a running view; what's pinned here is the one number that measurement can't decide — how
/// far the strip's own labels are allowed to grow before they start scrolling instead.
struct TabStripScalingTests {
    @Test("Everyday text sizes are passed through untouched")
    func everydaySizesAreUntouched() {
        for size in [DynamicTypeSize.xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge] {
            #expect(VFTabMetrics.clamped(size) == size, "\(size) is below the ceiling, so nothing changes")
        }
    }

    @Test("Labels stop growing at the ceiling")
    func clampStopsAtTheCeiling() {
        for size in [DynamicTypeSize.accessibility1, .accessibility2, .accessibility3,
                     .accessibility4, .accessibility5] {
            #expect(VFTabMetrics.clamped(size) == VFTabMetrics.maximumLabelSize)
        }
    }

    @Test("The ceiling is an accessibility size, not a refusal to scale")
    func ceilingIsAnAccessibilitySize() {
        #expect(VFTabMetrics.maximumLabelSize.isAccessibilitySize,
                "clamping below the accessibility sizes would ignore the setting outright")
        #expect(VFTabMetrics.maximumLabelSize > .xxxLarge)
    }

    @Test("The clamp never shrinks anything")
    func clampOnlyEverReduces() {
        for size in DynamicTypeSize.allCases {
            #expect(VFTabMetrics.clamped(size) <= size, "\(size) must never be scaled up")
            #expect(VFTabMetrics.clamped(size) == min(size, VFTabMetrics.maximumLabelSize))
        }
    }
}

/// The metadata lines under a recording title (Jeremy, 2026-09-20). Side by side in an HStack,
/// each piece got a share of the width and broke inside its own word — "1 speak / er". They're
/// joined into one Text now, which costs each piece its own VoiceOver label, so the whole line
/// carries one spoken string instead. That string is what's pinned here.
struct MetaLineTests {
    @Test("Pieces are separated for a listener, not with the printed middot")
    func spokenUsesCommas() {
        let line = VFMetaLine.spoken(["Sep 19 at 8:53 PM", "11 seconds", "1 speaker"])
        #expect(line == "Sep 19 at 8:53 PM, 11 seconds, 1 speaker")
        #expect(!line.contains(VFMetaLine.separator), "a middot reads as nothing useful aloud")
    }

    @Test("A piece that isn't there leaves no stray separator")
    func spokenDropsEmptyPieces() {
        #expect(VFMetaLine.spoken(["Sep 19", "", "1 speaker"]) == "Sep 19, 1 speaker")
        #expect(VFMetaLine.spoken(["Sep 19", "   "]) == "Sep 19", "whitespace isn't a piece either")
    }

    @Test("One piece, and nothing at all")
    func spokenEdges() {
        #expect(VFMetaLine.spoken(["0:11"]) == "0:11")
        #expect(VFMetaLine.spoken([]).isEmpty)
        #expect(VFMetaLine.spoken(["", "  "]).isEmpty)
    }
}
