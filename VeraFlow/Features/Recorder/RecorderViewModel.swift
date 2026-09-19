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
    /// A custom template on top of the base (v1.1 plan item 13), or nil for the built-in.
    private(set) var selectedCustomTemplate: CustomTemplate?
    /// The user's custom templates, for the picker.
    private(set) var customTemplates: [CustomTemplate] = []
    /// One line the summary should pay attention to (v1.1 plan item 13). Prefilled from the custom template.
    var focusDraft = ""
    /// Free bytes when the low-disk warning fired; `nil` when there is no warning.
    private(set) var lowDiskBytes: Int64?
    /// True after a phone call ends and the system says we may resume (SPEC §8.3).
    private(set) var isAskingToResume = false
    /// Short status line, e.g. after a headset disconnects.
    private(set) var notice: String?
    private(set) var errorMessage: String?
    var draftTitle = ""
    /// Words while recording (v1.1 plan item 4): what the two-line block shows.
    private(set) var preview = PreviewState()
    /// True while the preview analyzer is running.
    private(set) var isPreviewOn = false
    /// Why the preview isn't running when it could be expected to; shown nowhere yet, logged.
    private(set) var previewNotice: String?
    /// Foreground state, told by the screen; the preview stops in the background.
    private(set) var isSceneActive = true

    var isActive: Bool { phase == .recording || phase == .paused }

    static let inputChoiceKey = "recorder.inputChoice"

    private let services: AppServices
    private let context: ModelContext
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    /// Injected so tests can pretend the phone is hot.
    private let thermalState: @Sendable () -> ProcessInfo.ThermalState
    private var streamTasks: [Task<Void, Never>] = []
    private var previewTask: Task<Void, Never>?
    /// Last port handed to the recorder, so route-change reloads don't re-apply the same one.
    private var appliedInputID: String??

    init(
        services: AppServices,
        context: ModelContext,
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = { .now },
        thermalState: @escaping @Sendable () -> ProcessInfo.ThermalState = { ProcessInfo.processInfo.thermalState }
    ) {
        self.services = services
        self.context = context
        self.defaults = defaults
        self.now = now
        self.thermalState = thermalState
        self.inputChoice = AudioInputChoice(stored: defaults.string(forKey: Self.inputChoiceKey))
        self.selectedTemplate = AppPreferences.defaultTemplate(in: defaults)
    }

    /// Chooses the template the summary will use, and remembers it for next time.
    func selectTemplate(_ template: TemplateID) {
        selectedTemplate = template
        selectedCustomTemplate = nil
        AppPreferences.setDefaultTemplate(template, in: defaults)
        AppPreferences.setDefaultCustomTemplateID(nil, in: defaults)
    }

    /// A custom template: its base becomes the template, its focus prefills the focus line.
    func selectCustomTemplate(_ template: CustomTemplate) {
        selectedTemplate = template.base
        selectedCustomTemplate = template
        if focusDraft.trimmingCharacters(in: .whitespaces).isEmpty || focusDraft == selectedCustomTemplate?.focus {
            focusDraft = template.focus
        }
        AppPreferences.setDefaultTemplate(template.base, in: defaults)
        AppPreferences.setDefaultCustomTemplateID(template.id, in: defaults)
    }

    /// Reads the custom templates and restores the remembered one if it still exists.
    func loadTemplates() {
        customTemplates = (try? context.fetch(FetchDescriptor<CustomTemplate>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        if selectedCustomTemplate == nil, let id = AppPreferences.defaultCustomTemplateID(in: defaults) {
            if let template = customTemplates.first(where: { $0.id == id }) {
                selectedCustomTemplate = template
                selectedTemplate = template.base
                if focusDraft.isEmpty { focusDraft = template.focus }
            } else {
                AppPreferences.setDefaultCustomTemplateID(nil, in: defaults)
            }
        }
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

    /// Reloads the input list whenever a headset connects or disconnects (a USB microphone on
    /// the Mac). Call from the screen's `.task`; stops when that task is cancelled.
    func watchInputs() async {
        for await _ in RecorderPlatform.inputListChanges() {
            guard !Task.isCancelled else { return }
            await loadInputs()
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
        recording.customTemplateID = selectedCustomTemplate?.id
        recording.focus = FocusLine.sanitize(focusDraft)
        do {
            try services.storage.folder(for: recording.id, excludeFromBackup: !AppPreferences.includesRecordingsInBackup(in: defaults))
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
        await startPreviewIfPossible()
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
        await stopPreview()
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

    /// Throws the recording away from the naming step (Jeremy, 2026-09-19): the row, its marks and
    /// the audio all go. Nothing reaches the pipeline, so nothing is transcribed or summarized.
    /// Deliberately only reachable from `.naming` — once saved, deleting goes through the library,
    /// which keeps a recording in Recently Deleted for a while rather than destroying it.
    func discard() async {
        guard phase == .naming, let recording else { return }
        let id = recording.id
        context.delete(recording)
        do {
            try context.save()
        } catch {
            errorMessage = Self.message(for: error)
            return
        }
        try? services.storage.deleteFolder(for: id)
        self.recording = nil
        draftTitle = ""
        bookmarkCount = 0
        levelHistory = []
        labelableMark = nil
        lowDiskBytes = nil
        snapshot = RecorderSnapshot()
        phase = .idle
    }

    func dismissNotice() {
        notice = nil
    }

    // MARK: Live transcript preview (v1.1 plan item 4)

    /// The screen reports foreground changes. The preview stops in the background (the
    /// recording goes on; the file pass makes the real transcript) and comes back on return.
    func sceneDidChange(isActive: Bool) async {
        isSceneActive = isActive
        if !isActive {
            await stopPreview(clearing: true)
        } else if phase == .recording || phase == .paused {
            await startPreviewIfPossible()
        }
    }

    /// Thermal pressure: at `.serious` or worse the preview stops; it comes back once the
    /// phone cools, if still recording.
    func thermalDidChange() async {
        if Self.isTooHot(thermalState()) {
            if isPreviewOn { previewNotice = "Paused the live words to keep the \(Platform.deviceNoun) cool." }
            await stopPreview(clearing: false)
        } else if isActive {
            await startPreviewIfPossible()
        }
    }

    /// Reacts to thermal notifications until the enclosing task is cancelled.
    func watchThermalState() async {
        let center = NotificationCenter.default
        let observer = center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: nil) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.thermalDidChange() }
        }
        defer { center.removeObserver(observer) }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3600))
        }
    }

    static func isTooHot(_ state: ProcessInfo.ThermalState) -> Bool {
        state == .serious || state == .critical
    }

    /// Whether the preview should run now: the setting, the transcriber (never the dictation
    /// fallback), the foreground, and the phone's temperature all have to agree.
    private func startPreviewIfPossible() async {
        guard !isPreviewOn, isActive, let recording else { return }
        guard AppPreferences.showsLiveTranscript(in: defaults) else { return }
        guard isSceneActive, !Self.isTooHot(thermalState()) else { return }
        let locale = Locale(identifier: recording.localeIdentifier)
        guard await services.transcriptPreview.isAvailable(locale: locale) else {
            previewNotice = "Live words need the on-device speech model."
            return
        }
        do {
            let session = try await services.transcriptPreview.start(locale: locale)
            await services.recorder.setPreviewSink(session.sink)
            isPreviewOn = true
            previewNotice = nil
            previewTask?.cancel()
            previewTask = Task { @MainActor [weak self] in
                for await event in session.events {
                    guard let self, !Task.isCancelled else { return }
                    PreviewReducer.apply(event, to: &self.preview)
                }
            }
        } catch {
            Self.log.error("preview didn't start: \(error.localizedDescription, privacy: .public)")
            previewNotice = "Live words aren't available right now."
        }
    }

    private func stopPreview(clearing: Bool = true) async {
        previewTask?.cancel()
        previewTask = nil
        guard isPreviewOn else { return }
        isPreviewOn = false
        await services.recorder.setPreviewSink(nil)
        await services.transcriptPreview.stop()
        if clearing { preview = PreviewState() }
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
            notice = "Headset disconnected. Recording continues on the built-in microphone."
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

    /// What the Record screen says about a recorder failure. Internal so the copy is testable.
    static func message(for error: Error) -> String {
        if let error = error as? AudioRecorderError {
            switch error {
            case .permissionDenied:
                return "Microphone access is off. Turn it on in \(Platform.settingsAppName) to record."
            case .alreadyRecording:
                return "A recording is already in progress."
            case .notRecording:
                return "Nothing is recording right now."
            case .diskFull:
                return "Not enough free storage to record. Free up space and try again."
            case .sessionFailed(let detail):
                return "Recording couldn't start: \(detail)"
            case .noAudioCaptured(let detail):
                let reason = detail.map { " (\($0))" } ?? ""
                return "No audio was captured, so the recording is empty\(reason). Check the microphone in the Record screen and try again."
            }
        }
        return error.localizedDescription
    }
}
