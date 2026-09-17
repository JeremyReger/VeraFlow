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

    func run(
        title: String,
        work: @Sendable @escaping (_ progress: @Sendable @escaping (Double) -> Void) async -> Void
    ) async {
        let identifier = Self.identifierPrefix + UUID().uuidString.lowercased()
        let state = RunState()

        // Registered per run with a unique suffix: a second registration of the same identifier
        // kills the app, and continued-processing handlers may be registered lazily.
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let task = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
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
        await state.wait()
    }

    /// The system's task object isn't Sendable; the handler and the progress closure share it here.
    private final class TaskBox: @unchecked Sendable {
        let task: BGContinuedProcessingTask
        var expired = false
        init(_ task: BGContinuedProcessingTask) { self.task = task }
    }

    /// Lets `run` await the launch handler's completion.
    private final class RunState: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Void, Never>?
        private var finished = false

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
