import ActivityKit
import Foundation
import os

/// ActivityKit-backed Live Activity. Failures are logged, never surfaced: the recording matters,
/// the banner is a convenience. No push token, no network (SPEC §14.1).
actor LiveRecordingActivityService: RecordingActivityService {
    private static let log = Logger(subsystem: "com.jeremyreger.veraflow", category: "activity")

    private var activity: Activity<RecordingActivityAttributes>?

    func start(recordingID: UUID, title: String, state: RecordingActivityAttributes.ContentState) async {
        await endAll()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            Self.log.info("Live Activities are off in Settings; not showing the recording banner")
            return
        }
        do {
            activity = try Activity.request(
                attributes: RecordingActivityAttributes(recordingID: recordingID, title: title),
                content: ActivityContent(state: state, staleDate: nil)
            )
            Self.log.info("activity started for \(recordingID.uuidString, privacy: .public)")
        } catch {
            Self.log.error("could not start the Live Activity: \(error.localizedDescription, privacy: .public)")
        }
    }

    func update(_ state: RecordingActivityAttributes.ContentState) async {
        await activity?.update(ActivityContent(state: state, staleDate: nil))
    }

    func end() async {
        if let activity {
            await activity.end(nil, dismissalPolicy: .immediate)
            self.activity = nil
        }
        await endAll()
    }

    /// Ends activities left behind by a crash or force-quit so two banners never stack.
    private func endAll() async {
        for stale in Activity<RecordingActivityAttributes>.activities {
            await stale.end(nil, dismissalPolicy: .immediate)
        }
    }
}
