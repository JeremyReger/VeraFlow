import Foundation
import Observation
import SwiftData

/// Drives the recording screen (SPEC §4.2, §8): permission, start/pause/resume/stop,
/// bookmarks, interruptions, disk space, and the naming step after stop.
@Observable
@MainActor
final class RecorderViewModel {
    enum Phase: Equatable {
        case idle
        case permissionDenied
        case recording
        case paused
        /// Stopped; waiting for the user to confirm a title.
        case naming
        case saved(recordingID: UUID)
    }

    private(set) var phase: Phase = .idle
    private(set) var snapshot = RecorderSnapshot()
    private(set) var recording: Recording?
    private(set) var bookmarkCount = 0
    private(set) var inputs: [AudioInputOption] = []
    private(set) var selectedInputID: String?
    /// Free bytes when the low-disk warning fired; `nil` when there is no warning.
    private(set) var lowDiskBytes: Int64?
    /// True after a phone call ends and the system says we may resume (SPEC §8.3).
    private(set) var isAskingToResume = false
    /// Short status line, e.g. after a headset disconnects.
    private(set) var notice: String?
    private(set) var errorMessage: String?
    var draftTitle = ""

    var isActive: Bool { phase == .recording || phase == .paused }

    private let services: AppServices
    private let context: ModelContext
    private let now: @Sendable () -> Date
    private var streamTasks: [Task<Void, Never>] = []

    init(services: AppServices, context: ModelContext, now: @escaping @Sendable () -> Date = { .now }) {
        self.services = services
        self.context = context
        self.now = now
    }

    // MARK: Inputs

    func loadInputs() async {
        inputs = await services.recorder.availableInputs()
        if let selectedInputID, !inputs.contains(where: { $0.id == selectedInputID }) {
            self.selectedInputID = nil
        }
    }

    func selectInput(id: String?) async {
        do {
            try await services.recorder.selectInput(id: id)
            selectedInputID = id
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    // MARK: Recording

    func start() async {
        guard phase == .idle || phase == .permissionDenied else { return }
        errorMessage = nil
        guard await services.recorder.requestPermission() else {
            phase = .permissionDenied
            return
        }

        // Subscribe before starting so no snapshot or interruption is missed.
        let snapshots = await services.recorder.snapshots()
        let interruptions = await services.recorder.interruptions()

        let startedAt = now()
        let recording = Recording(title: Recording.suggestedTitle(for: startedAt), createdAt: startedAt, stage: .recording)
        do {
            try services.storage.folder(for: recording.id)
            let url = services.storage.audioURL(for: recording.id, fileName: recording.audioFileName)
            context.insert(recording)
            try context.save()
            try await services.recorder.start(to: url)
        } catch {
            context.delete(recording)
            try? context.save()
            try? services.storage.deleteFolder(for: recording.id)
            errorMessage = Self.message(for: error)
            return
        }

        self.recording = recording
        draftTitle = recording.title
        bookmarkCount = 0
        lowDiskBytes = nil
        notice = nil
        phase = .recording
        observe(snapshots: snapshots, interruptions: interruptions)
    }

    func pause() async {
        guard phase == .recording else { return }
        do {
            try await services.recorder.pause()
            phase = .paused
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func resume() async {
        guard phase == .paused else { return }
        isAskingToResume = false
        do {
            try await services.recorder.resume()
            phase = .recording
            notice = nil
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// Stops capture and moves to the naming step. The file is final after this.
    func stop() async {
        guard isActive, let recording else { return }
        isAskingToResume = false
        do {
            let result = try await services.recorder.stop()
            recording.duration = result.duration
            try context.save()
        } catch {
            errorMessage = Self.message(for: error)
        }
        cancelStreams()
        snapshot.status = .idle
        snapshot.level = 0
        phase = .naming
    }

    func addBookmark(note: String? = nil) async {
        guard isActive, let recording else { return }
        let time = await services.recorder.currentTime()
        insertBookmark(time: time, note: note, into: recording)
    }

    /// Answer to the "Resume recording?" prompt after an interruption.
    func answerResumePrompt(resume: Bool) async {
        isAskingToResume = false
        if resume {
            await self.resume()
        }
    }

    /// Confirms the title and hands the recording to the pipeline (SPEC §4.2 step 4).
    func save() async {
        guard phase == .naming, let recording else { return }
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        recording.title = trimmed.isEmpty ? Recording.suggestedTitle(for: recording.createdAt) : trimmed
        recording.stage = .recorded
        do {
            try context.save()
        } catch {
            errorMessage = Self.message(for: error)
            return
        }
        await services.pipeline.enqueue(recordingID: recording.id)
        phase = .saved(recordingID: recording.id)
    }

    func dismissNotice() {
        notice = nil
    }

    func dismissError() {
        errorMessage = nil
    }

    // MARK: Recorder events

    private func observe(snapshots: AsyncStream<RecorderSnapshot>, interruptions: AsyncStream<RecorderInterruption>) {
        cancelStreams()
        streamTasks.append(Task { @MainActor [weak self] in
            for await snapshot in snapshots {
                guard let self else { return }
                self.apply(snapshot)
            }
        })
        streamTasks.append(Task { @MainActor [weak self] in
            for await interruption in interruptions {
                guard let self else { return }
                await self.handle(interruption)
            }
        })
    }

    private func apply(_ snapshot: RecorderSnapshot) {
        guard isActive else { return }
        self.snapshot = snapshot
        switch snapshot.status {
        case .recording where phase == .paused:
            phase = .recording
        case .paused where phase == .recording:
            phase = .paused
        default:
            break
        }
    }

    private func handle(_ interruption: RecorderInterruption) async {
        guard isActive, let recording else { return }
        switch interruption {
        case .began:
            phase = .paused
            let time = await services.recorder.currentTime()
            insertBookmark(time: time, note: "Interrupted", into: recording)
            notice = "Paused by a call or another app."
        case .ended(let shouldResume):
            if shouldResume {
                isAskingToResume = true
            } else {
                notice = "Paused. Tap Resume to keep recording."
            }
        case .routeChanged:
            notice = "Headset disconnected. Recording continues on the iPhone microphone."
        case .lowDiskSpace(let bytes):
            lowDiskBytes = bytes
        case .diskFull(let bytes):
            lowDiskBytes = bytes
            notice = "Storage is full. Recording stopped and saved."
            await stop()
        }
    }

    private func insertBookmark(time: TimeInterval, note: String?, into recording: Recording) {
        let bookmark = Bookmark(time: time, note: note)
        context.insert(bookmark)
        bookmark.recording = recording
        do {
            try context.save()
        } catch {
            errorMessage = Self.message(for: error)
        }
        bookmarkCount = recording.bookmarks.count
    }

    private func cancelStreams() {
        for task in streamTasks {
            task.cancel()
        }
        streamTasks.removeAll()
    }

    private static func message(for error: Error) -> String {
        if let error = error as? AudioRecorderError {
            switch error {
            case .permissionDenied:
                return "Microphone access is off. Turn it on in Settings to record."
            case .alreadyRecording:
                return "A recording is already in progress."
            case .notRecording:
                return "Nothing is recording right now."
            case .diskFull:
                return "Not enough free storage to record. Free up space and try again."
            case .sessionFailed(let detail):
                return "Recording couldn't start: \(detail)"
            }
        }
        return error.localizedDescription
    }
}
