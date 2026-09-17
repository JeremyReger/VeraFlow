import Foundation
import Testing
@testable import VeraFlow

struct RecordingActivityStateTests {
    private let now = Date(timeIntervalSince1970: 1_789_000_000)

    @Test("Recording state counts up from now minus the audio written so far")
    func recording() {
        let state = RecordingActivityAttributes.ContentState.make(elapsed: 90, isPaused: false, bookmarkCount: 2, now: now)
        #expect(state.startedAt == now.addingTimeInterval(-90))
        #expect(state.pausedAt == nil)
        #expect(!state.isPaused)
        #expect(state.bookmarkCount == 2)
    }

    @Test("Paused state freezes the timer at now")
    func paused() {
        let state = RecordingActivityAttributes.ContentState.make(elapsed: 12.5, isPaused: true, bookmarkCount: 0, now: now)
        #expect(state.isPaused)
        #expect(state.pausedAt == now)
        // What the widget shows: pausedAt - startedAt = elapsed.
        #expect(abs(state.pausedAt!.timeIntervalSince(state.startedAt) - 12.5) < 0.001)
    }

    @Test("Negative elapsed is treated as zero")
    func clampsElapsed() {
        let state = RecordingActivityAttributes.ContentState.make(elapsed: -5, isPaused: false, bookmarkCount: 0, now: now)
        #expect(state.startedAt == now)
    }

    @Test("State survives the JSON round trip ActivityKit uses")
    func codable() throws {
        let state = RecordingActivityAttributes.ContentState.make(elapsed: 42, isPaused: true, bookmarkCount: 3, now: now)
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(RecordingActivityAttributes.ContentState.self, from: data)
        #expect(decoded == state)
    }
}
