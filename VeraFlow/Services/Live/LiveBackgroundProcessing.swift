import BackgroundTasks
import Foundation
import os

/// Wraps pipeline work in a `BGContinuedProcessingTask` (iOS 26) so it keeps running after the
/// user leaves the app, with the system's progress UI (SPEC §6.3). Falls back to running the
/// work inline when the system won't take the task (Simulator, background refresh off, app not
/// in the foreground, or a launch-time resume that no user action started).
final class LiveBackgroundProcessing: BackgroundProcessing, Sendable {
    private static let log = Logger(subsystem: "com.jeremyreger.veraflow", category: "background")
    /// Must match the wildcard entry in Info.plist `BGTaskSchedulerPermittedIdentifiers`.
    static let identifierPrefix = "com.jeremyreger.veraflow.processing."
    /// How long to wait for the system to launch the task before running the work inline. On
    /// iOS 27 with the iOS 26.5 SDK the submission "succeeds" but the launch never comes (the
    /// scheduler's reply can't be decoded), so this is what keeps the pipeline moving.
    static let launchTimeout: Duration = .seconds(3)
    /// Once the system fails to launch a task in this session, stop asking: each unanswered
    /// request shows a "Processing recordings · Task failed" card on the Lock Screen.
    private let launchFailed = LaunchFlag()

    func run(
        title: String,
        work: @Sendable @escaping (_ progress: @Sendable @escaping (Double) -> Void) async -> Void
    ) async {
        guard !launchFailed.value else {
            await work { _ in }
            return
        }
        let identifier = Self.identifierPrefix + UUID().uuidString.lowercased()
        let state = RunState()

        // Registered per run with a unique suffix: a second registration of the same identifier
        // kills the app, and continued-processing handlers may be registered lazily.
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let task = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            // If the wait below already gave up and ran the work inline, just close the task.
            guard state.claim() else {
                task.setTaskCompleted(success: true)
                return
            }
            let box = TaskBox(task)
            box.task.progress.totalUnitCount = 100
            let job = Task {
                await work { fraction in
                    let units = Int64((max(0, min(1, fraction)) * 100).rounded())
                    box.task.progress.completedUnitCount = units
                    box.task.updateTitle(box.task.title, subtitle: "\(units)% done")
                }
                box.task.setTaskCompleted(success: !box.expired)
                state.finish()
            }
            box.task.expirationHandler = {
                box.expired = true
                job.cancel()
            }
        }

        guard registered else {
            Self.log.error("background task identifier not permitted; running inline")
            await work { _ in }
            return
        }

        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: title, subtitle: "Starting…")
        // If it can't start right now, run in the foreground instead of waiting in a queue.
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            Self.log.info("continued processing unavailable (\(error.localizedDescription, privacy: .public)); running inline")
            await work { _ in }
            return
        }
        let deadline = ContinuousClock.now + Self.launchTimeout
        while !state.isClaimed, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if !state.isClaimed, state.claim() {
            Self.log.notice("system did not launch the processing task in time; running inline for the rest of this session")
            launchFailed.value = true
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
            await work { _ in }
            return
        }
        await state.wait()
    }

    private final class LaunchFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var _value = false
        var value: Bool {
            get { lock.withLock { _value } }
            set { lock.withLock { _value = newValue } }
        }
    }

    /// The system's task object isn't Sendable; the handler and the progress closure share it here.
    private final class TaskBox: @unchecked Sendable {
        let task: BGContinuedProcessingTask
        var expired = false
        init(_ task: BGContinuedProcessingTask) { self.task = task }
    }

    /// Lets `run` await the launch handler's completion, and decides who runs the work: the
    /// system's launch handler or the inline fallback, never both.
    private final class RunState: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Void, Never>?
        private var finished = false
        private var claimed = false

        /// True for the first caller only.
        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if claimed { return false }
            claimed = true
            return true
        }

        var isClaimed: Bool {
            lock.lock()
            defer { lock.unlock() }
            return claimed
        }

        func finish() {
            lock.lock()
            finished = true
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()
            continuation?.resume()
        }

        func wait() async {
            await withCheckedContinuation { continuation in
                lock.lock()
                if finished {
                    lock.unlock()
                    continuation.resume()
                } else {
                    self.continuation = continuation
                    lock.unlock()
                }
            }
        }
    }
}
