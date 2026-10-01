import SwiftUI
import Testing
@testable import VeraFlow

/// The glass pass (2026-10-01). What matters here isn't the blur, it's the promise that every
/// frosted surface has a flat one to fall back to: Reduce Transparency and Increase Contrast must
/// return the app to the palette it shipped with, not to a dimmer version of the glass. A role
/// added later without a fallback is an accessibility regression, so the list is checked whole.
struct SurfaceRoleTests {
    @Test("Every role falls back to a palette surface, not to glass")
    func everyRoleHasAnOpaqueFallback() {
        let palette = [VFColor.surface, VFColor.surfaceRaised, VFColor.playerBar]
        for role in VFSurfaceRole.allCases {
            #expect(palette.contains(role.opaqueColor), "\(role) has no flat surface to fall back to")
        }
    }

    @Test("Only the panel roles draw a rim; the full-bleed bars would draw a box")
    func rimsBelongToPanels() {
        #expect(VFSurfaceRole.card.drawsRim)
        #expect(VFSurfaceRole.raised.drawsRim)
        #expect(!VFSurfaceRole.chrome.drawsRim)
        #expect(!VFSurfaceRole.content.drawsRim)
    }

    @Test("Every role lifts off the backdrop")
    func everyRoleHasShadow() {
        for role in VFSurfaceRole.allCases {
            #expect(role.shadow.radius > 0, "\(role) sits flat in the backdrop instead of in front of it")
            #expect(role.shadow.opacity > 0)
        }
    }
}
