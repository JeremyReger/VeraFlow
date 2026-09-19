import Foundation
import Testing
@testable import VeraFlow

/// The rule that tells a real hardware change from the one the Mac's own device binding posts.
/// Jeremy's first native Mac recordings were empty because every configuration change rebuilt
/// the engine, and rebuilding bound the device again, which posted another one (2026-09-19).
struct CaptureRestartTests {
    private let tapped = CaptureState(sampleRate: 44_100, channels: 1, deviceID: 42)

    @Test("A change that moved neither the format nor the device keeps the tap")
    func nothingMoved() {
        #expect(CaptureRestart.decide(tapped: tapped, current: tapped) == .keepTap)
    }

    @Test("A new sample rate or channel count rebuilds")
    func formatMoved() {
        #expect(CaptureRestart.decide(tapped: tapped, current: CaptureState(sampleRate: 48_000, channels: 1, deviceID: 42)) == .rebuild)
        #expect(CaptureRestart.decide(tapped: tapped, current: CaptureState(sampleRate: 44_100, channels: 2, deviceID: 42)) == .rebuild)
    }

    @Test("A different input device rebuilds: the USB microphone was unplugged")
    func deviceMoved() {
        #expect(CaptureRestart.decide(tapped: tapped, current: CaptureState(sampleRate: 44_100, channels: 1, deviceID: 7)) == .rebuild)
        #expect(CaptureRestart.decide(tapped: tapped, current: CaptureState(sampleRate: 44_100, channels: 1, deviceID: nil)) == .rebuild)
    }

    @Test("A format the engine can't report yet is not read as a change")
    func settling() {
        #expect(CaptureRestart.decide(tapped: tapped, current: CaptureState(sampleRate: 0, channels: 0, deviceID: 42)) == .keepTap)
        #expect(CaptureRestart.decide(tapped: tapped, current: CaptureState(sampleRate: 44_100, channels: 0, deviceID: 42)) == .keepTap)
    }

    @Test("On iOS there is no bound device, so only the format decides")
    func withoutADevice() {
        let session = CaptureState(sampleRate: 48_000, channels: 1)
        #expect(session.deviceID == nil)
        #expect(CaptureRestart.decide(tapped: session, current: session) == .keepTap)
        #expect(CaptureRestart.decide(tapped: session, current: CaptureState(sampleRate: 16_000, channels: 1)) == .rebuild)
    }

    @Test("The same decision repeated never flips: a settled capture stays settled")
    func stable() {
        // The loop that emptied the recordings was this call answering .rebuild forever for a
        // capture that never actually changed.
        for _ in 0..<50 {
            #expect(CaptureRestart.decide(tapped: tapped, current: tapped) == .keepTap)
        }
    }
}
