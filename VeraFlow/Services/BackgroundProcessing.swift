import Foundation

/// Runs a unit of pipeline work so it can keep going after the user leaves the app (SPEC §6.3).
/// The live implementation wraps a `BGContinuedProcessingTask`; the fake just runs the work.
protocol BackgroundProcessing: Sendable {
    /// Runs `work`. `progress` takes 0...1 and feeds the system's progress UI. If the system
    /// expires the task, the task running `work` is cancelled; `work` must save partial state
    /// when it sees cancellation and return promptly.
    func run(
        title: String,
        work: @Sendable @escaping (_ progress: @Sendable @escaping (Double) -> Void) async -> Void
    ) async
}

/// Runs the work inline. Tests can make it expire after a delay to exercise re-queueing.
actor FakeBackgroundProcessing: BackgroundProcessing {
    private(set) var runTitles: [String] = []
    private(set) var lastProgress: Double = 0
    /// If set, the work is cancelled this long after it starts (simulates system expiration).
    var expireAfter: Duration?

    func run(
        title: String,
        work: @Sendable @escaping (_ progress: @Sendable @escaping (Double) -> Void) async -> Void
    ) async {
        runTitles.append(title)
        let expireAfter = self.expireAfter
        let task = Task { [weak self] in
            await work { fraction in
                Task { await self?.record(progress: fraction) }
            }
        }
        if let expireAfter {
            Task {
                try? await Task.sleep(for: expireAfter)
                task.cancel()
            }
        }
        await task.value
    }

    func setExpireAfter(_ duration: Duration?) {
        expireAfter = duration
    }

    private func record(progress: Double) {
        lastProgress = progress
    }
}
