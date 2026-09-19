import AVFAudio
import Foundation
import Observation
import OSLog
import SwiftData

/// One bar of the live waveform.
struct WaveformSample: Equatable, Sendable {
    var level: Float
    /// A bookmark (manual or "Interrupted") was added at this moment.
    var isBookmark = false
}

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

    /// How many recent level samples the waveform keeps (about 10 s at 10 Hz).
    static let waveformSampleCount = 100

    private(set) var phase: Phase = .idle
    private(set) var snapshot = RecorderSnapshot()
    /// Recent input levels, oldest first, for the live waveform. Paused time adds zeros.
    private(set) var levelHistory: [WaveformSample] = []
    private(set) var recording: Recording?
    private(set) var bookmarkCount = 0
    /// The mark just added, while its label chips are showing (v1.1 plan item 1).
    private(set) var labelableMark: Bookmark?
    /// How long the label chips stay after Mark.
    static let labelWindow: Duration = .seconds(4)
    private var labelWindowTask: Task<Void, Never>?
    private(set) var inputs: [AudioInputOption] = []
    /// The port currently preferred; `nil` while iOS is choosing. Drives the picker's label.
    private(set) var selectedInputID: String?
    /// What the user asked for (remembered in `UserDefaults`).
    private(set) var inputChoice: AudioInputChoice
    /// Summary template for the next recording, picked before recording starts (design spec §4).
    private(set) var selectedTemplate: TemplateID
    /// Free bytes when the low-disk warning fired; `nil` when there is no warning.
    private(set) var lowDiskBytes: Int64?
    /// True after a phone call ends and the system says we may resume (SPEC §8.3).
    private(set) var isAskingToResume = false
    /// Short status line, e.g. after a headset disconnects.
    private(set) var notice: String?
    private(set) var errorMessage: String?
    var draftTitle = ""

    var isActive: Bool { phase == .recording || phase == .paused }

    static let inputChoiceKey = "recorder.inputChoice"

    private let services: AppServices
    private let context: ModelContext
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    private var streamTasks: [Task<Void, Never>] = []
    private var routeObserver: (any NSObjectProtocol)?
    /// Last port handed to the recorder, so route-change reloads don't re-apply the same one.
    private var appliedInputID: String??

    init(
        services: AppServices,
        context: ModelContext,
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.services = services
        self.context = context
        self.defaults = defaults
        self.now = now
        self.inputChoice = AudioInputChoice(stored: defaults.string(forKey: Self.inputChoiceKey))
        self.selectedTemplate = AppPreferences.defaultTemplate(in: defaults)
    }

    /// Chooses the template the summary will use, and remembers it for next time.
    func selectTemplate(_ template: TemplateID) {
        selectedTemplate = template
        AppPreferences.setDefaultTemplate(template, in: defaults)
    }

    // MARK: Inputs

    /// Reads what's plugged in and applies the remembered choice (built-in mic by default).
    /// Safe to call often: the recorder is told once per choice, not on every route change.
    /// Route changes are noisy (the port being switched to can be missing from the list for a
    /// moment); pushing a fallback then would undo the switch the user just asked for.
    func loadInputs() async {
        inputs = await services.recorder.availableInputs()
        await applyInputChoice()
    }

    private static let log = Logger(subsystem: "com.jeremyreger.veraflow", category: "recorder-ui")

    /// The user picked a microphone (`nil` = let iOS choose). Remembered for next time.
    func selectInput(id: String?) async {
        Self.log.info("mic tap: \(id ?? "automatic", privacy: .public); listed \(self.inputs.map(\.id).joined(separator: ","), privacy: .public); phase \(String(describing: self.phase), privacy: .public)")
        inputChoice = id.map { .device($0) } ?? .automatic
        defaults.set(inputChoice.stored, forKey: Self.inputChoiceKey)
        appliedInputID = nil
        await applyInputChoice()
    }

    /// Reloads the input list whenever a headset connects or disconnects. Call from the
    /// screen's `.task`; stops when that task is cancelled.
    func watchInputs() async {
        let center = NotificationCenter.default
        let observer = center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.loadInputs() }
        }
        routeObserver = observer
        defer {
            center.removeObserver(observer)
            routeObserver = nil
        }
        // Hold until the enclosing SwiftUI task is cancelled.
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3600))
        }
    }

    private func applyInputChoice() async {
        let effective = AudioInputPolicy.effectiveInput(available: inputs, choice: inputChoice)
        selectedInputID = effective
        // Only the first load and an explicit tap reach the recorder. It keeps the wanted port
        // itself, ignores it while unplugged, and iOS already falls back to the phone mic.
        guard appliedInputID == nil else { return }
        do {
            try await services.recorder.selectInput(id: effective)
            appliedInputID = .some(effective)
        } catch {
            Self.log.error("mic choice \(effective ?? "automatic", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
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
        let recording = Recording(
            title: Recording.suggestedTitle(for: startedAt),
            createdAt: startedAt,
            stage: .recording,
            localeIdentifier: AppPreferences.effectiveTranscriptionLocale(in: defaults).identifier(.bcp47),
            templateID: selectedTemplate
        )
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
        levelHistory = []
        lowDiskBytes = nil
        notice = nil
        phase = .recording
        observe(snapshots: snapshots, interruptions: interruptions)
        // Lock Screen / Dynamic Island buttons arrive here while this recording is live.
        RecordingControlHub.shared.handler = { [weak self] action in
            guard let self else { return }
            switch action {
            case .pause: await self.pause()
            case .resume: await self.resume()
            case .bookmark: await self.addBookmark()
            }
        }
        await services.activity.start(recordingID: recording.id, title: recording.title, state: activityState())
    }

    func pause() async {
        guard phase == .recording else { return }
        do {
            try await services.recorder.pause()
            phase = .paused
            await syncActivity()
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
            await syncActivity()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// Stops capture and moves to the naming step. The file is final after this.
    func stop() async {
        guard isActive, let recording else { return }
        isAskingToResume = false
        RecordingControlHub.shared.handler = nil
        await services.activity.end()
        do {
            let result = try await services.recorder.stop()
            recording.duration = result.duration
            try context.save()
        } catch {
            errorMessage = Self.message(for: error)
        }
        cancelStreams()
        labelWindowTask?.cancel()
        labelableMark = nil
        snapshot.status = .idle
        snapshot.level = 0
        phase = .naming
    }

    func addBookmark(note: String? = nil) async {
        guard isActive, let recording else { return }
        let time = await services.recorder.currentTime()
        await insertBookmark(time: time, note: note, into: recording)
    }

    /// The Mark button: adds the mark and offers the quick labels for a few seconds.
    func mark() async {
        guard isActive, let recording else { return }
        let time = await services.recorder.currentTime()
        let bookmark = await insertBookmark(time: time, note: nil, into: recording)
        labelableMark = bookmark
        labelWindowTask?.cancel()
        labelWindowTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.labelWindow)
            guard !Task.isCancelled else { return }
            self?.labelableMark = nil
        }
    }

    /// One of the quick labels for the mark just added; the chips go away after.
    func labelLastMark(_ label: String) {
        guard let mark = labelableMark else { return }
        mark.note = label
        try? context.save()
        labelWindowTask?.cancel()
        labelableMark = nil
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

    /// Timer and level only. Snapshots are buffered, so a stale one can arrive after Pause;
    /// phase changes come from our own calls and from interruption events, never from here.
    /// While paused nothing is appended, so the waveform stands still instead of scrolling
    /// empty bars in from the right.
    private func apply(_ snapshot: RecorderSnapshot) {
        guard isActive else { return }
        self.snapshot = snapshot
        if phase == .recording {
            appendLevel(snapshot.level)
        }
    }

    private func handle(_ interruption: RecorderInterruption) async {
        guard isActive, let recording else { return }
        switch interruption {
        case .began:
            phase = .paused
            let time = await services.recorder.currentTime()
            await insertBookmark(time: time, note: Bookmark.interruptedNote, into: recording)
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

    private func appendLevel(_ level: Float) {
        levelHistory.append(WaveformSample(level: level))
        if levelHistory.count > Self.waveformSampleCount {
            levelHistory.removeFirst(levelHistory.count - Self.waveformSampleCount)
        }
    }

    /// Flags the newest waveform bar so the bookmark shows where it was added.
    private func markBookmarkOnWaveform() {
        if levelHistory.isEmpty {
            levelHistory.append(WaveformSample(level: 0, isBookmark: true))
        } else {
            levelHistory[levelHistory.count - 1].isBookmark = true
        }
    }

    @discardableResult
    private func insertBookmark(time: TimeInterval, note: String?, into recording: Recording) async -> Bookmark {
        let bookmark = Bookmark(time: time, note: note, kind: note == Bookmark.interruptedNote ? .interrupted : .manual)
        context.insert(bookmark)
        bookmark.recording = recording
        do {
            try context.save()
        } catch {
            errorMessage = Self.message(for: error)
        }
        bookmarkCount = recording.bookmarks.count
        markBookmarkOnWaveform()
        await syncActivity()
        return bookmark
    }

    // MARK: Live Activity

    /// Lock Screen / Dynamic Island state derived from what the recorder has written so far.
    private func activityState() -> RecordingActivityAttributes.ContentState {
        .make(elapsed: snapshot.elapsed, isPaused: phase == .paused, bookmarkCount: bookmarkCount, now: now())
    }

    /// Called on every transition (pause, resume, bookmark). The timer ticks by itself between calls.
    private func syncActivity() async {
        guard isActive else { return }
        await services.activity.update(activityState())
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
