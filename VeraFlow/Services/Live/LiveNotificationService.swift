import Foundation
import os
import UserNotifications

/// `UNUserNotificationCenter` for the "Summary ready" and "Needs attention" notifications
/// (v1.1 plan item 6). Provisional authorization first: the notification lands quietly in
/// Notification Center with no prompt, and the user can promote it there or from Settings.
///
/// Compiled against the iOS 26.5 SDK on 2026-09-19: `UNAuthorizationOptions.provisional`, `UNUserNotificationCenter`
/// delegate methods, `UNNotificationInterruptionLevel`.
final class LiveNotificationService: NSObject, NotificationService, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private static let log = Logger(subsystem: "com.jeremyreger.veraflow", category: "notifications")
    private static let recordingKey = "recordingID"

    private let center = UNUserNotificationCenter.current()
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<UUID>.Continuation] = [:]
    /// A tap that arrived before anyone listened (the app was launched by the notification).
    private var pendingTap: UUID?
    private var hasRequestedProvisional = false

    override init() {
        super.init()
        // Set at launch so a tap that starts the app is delivered here.
        center.delegate = self
    }

    // MARK: NotificationService

    func requestProvisionalAuthorization() async {
        let alreadyRequested = lock.withLock { () -> Bool in
            defer { hasRequestedProvisional = true }
            return hasRequestedProvisional
        }
        guard !alreadyRequested else { return }
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .provisional])
        } catch {
            Self.log.error("provisional authorization failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            Self.log.error("authorization failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func post(_ notification: ProcessingNotification) async {
        await requestProvisionalAuthorization()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            Self.log.info("not authorized; skipping \(notification.title, privacy: .public)")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.recordingTitle
        content.threadIdentifier = "processing"
        content.interruptionLevel = .active
        content.userInfo = [Self.recordingKey: notification.recordingID.uuidString]
        let request = UNNotificationRequest(identifier: notification.identifier, content: content, trigger: nil)
        do {
            try await center.add(request)
        } catch {
            Self.log.error("could not post \(notification.title, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func clear(recordingID: UUID) async {
        let identifier = ProcessingNotification(kind: .summaryReady, recordingID: recordingID, recordingTitle: "").identifier
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func taps() async -> AsyncStream<UUID> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<UUID>.makeStream()
        let pending = lock.withLock { () -> UUID? in
            continuations[id] = continuation
            defer { pendingTap = nil }
            return pendingTap
        }
        continuation.onTermination = { [weak self] _ in
            self?.lock.withLock { self?.continuations[id] = nil }
        }
        if let pending {
            continuation.yield(pending)
        }
        return stream
    }

    // MARK: UNUserNotificationCenterDelegate

    /// While the app is in the foreground nothing is posted; if one slips through, show it quietly.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        guard let raw = response.notification.request.content.userInfo[Self.recordingKey] as? String,
              let id = UUID(uuidString: raw) else { return }
        let targets = lock.withLock { () -> [AsyncStream<UUID>.Continuation] in
            let values = Array(continuations.values)
            if values.isEmpty { pendingTap = id }
            return values
        }
        for continuation in targets {
            continuation.yield(id)
        }
    }
}
