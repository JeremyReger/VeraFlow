import Foundation

/// Drives the recording Live Activity (SPEC §4.2 step 3, §8.4). The view model calls this on every
/// state change; the widget extension renders it. A fake keeps tests and the Simulator quiet.
protocol RecordingActivityService: Sendable {
    /// Starts a new activity for this recording, ending any stale one first.
    func start(recordingID: UUID, title: String, state: RecordingActivityAttributes.ContentState) async
    /// Pushes a new timer/pause/bookmark state. No-op when nothing is running.
    func update(_ state: RecordingActivityAttributes.ContentState) async
    /// Removes the activity from the Lock Screen and Dynamic Island right away.
    func end() async
}

/// Records calls so tests can assert what the Lock Screen would have shown.
actor FakeRecordingActivityService: RecordingActivityService {
    private(set) var startedRecordingID: UUID?
    private(set) var startedTitle: String?
    /// Every state pushed, in order; the first is the one passed to `start`.
    private(set) var states: [RecordingActivityAttributes.ContentState] = []
    private(set) var endCount = 0
    private(set) var isActive = false

    var latestState: RecordingActivityAttributes.ContentState? { states.last }

    func start(recordingID: UUID, title: String, state: RecordingActivityAttributes.ContentState) async {
        startedRecordingID = recordingID
        startedTitle = title
        states = [state]
        isActive = true
    }

    func update(_ state: RecordingActivityAttributes.ContentState) async {
        guard isActive else { return }
        states.append(state)
    }

    func end() async {
        guard isActive else { return }
        isActive = false
        endCount += 1
    }
}
