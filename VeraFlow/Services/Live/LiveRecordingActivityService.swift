#if canImport(ActivityKit)
import ActivityKit
import Foundation
import os

/// ActivityKit-backed Live Activity. Failures are logged, never surfaced: the recording matters,
/// the banner is a convenience. No push token, no network (SPEC §14.1).
///
/// `Activity` isn't `Sendable`, so the actor never stores one; it keeps the id and looks the
/// activity up in `Activity.activities` from nonisolated helpers on every call.
actor LiveRecordingActivityService: RecordingActivityService {
    private static let log = Logger(subsystem: "com.jeremyreger.veraflow", category: "activity")

    private var activityID: String?

    func start(recordingID: UUID, title: String, state: RecordingActivityAttributes.ContentState) async {
        await Self.endAll()
        activityID = nil
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            Self.log.info("Live Activities are off in Settings; not showing the recording banner")
            return
        }
        activityID = Self.request(
            attributes: RecordingActivityAttributes(recordingID: recordingID, title: title),
            content: ActivityContent(state: state, staleDate: nil)
        )
    }

    func update(_ state: RecordingActivityAttributes.ContentState) async {
        guard let activityID else { return }
        await Self.update(id: activityID, content: ActivityContent(state: state, staleDate: nil))
    }

    func end() async {
        activityID = nil
        await Self.endAll()
    }

    // MARK: Nonisolated ActivityKit calls (the Activity object never leaves these functions)

    private nonisolated static func request(
        attributes: RecordingActivityAttributes,
        content: ActivityContent<RecordingActivityAttributes.ContentState>
    ) -> String? {
        do {
            let activity = try Activity.request(attributes: attributes, content: content)
            log.info("activity started for \(attributes.recordingID.uuidString, privacy: .public)")
            return activity.id
        } catch {
            log.error("could not start the Live Activity: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private nonisolated static func update(id: String, content: ActivityContent<RecordingActivityAttributes.ContentState>) async {
        for activity in Activity<RecordingActivityAttributes>.activities where activity.id == id {
            await activity.update(content)
        }
    }

    /// Ends every activity of ours, including any left behind by a crash or force-quit,
    /// so two banners never stack.
    private nonisolated static func endAll() async {
        for activity in Activity<RecordingActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
#endif
