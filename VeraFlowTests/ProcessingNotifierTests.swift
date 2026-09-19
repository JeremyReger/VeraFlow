import Foundation
import Testing
@testable import VeraFlow

/// Which pipeline events become local notifications (v1.1 plan item 6).
struct ProcessingNotifierTests {
    private let id = UUID()

    @Test("Ready while the app is away announces once; ready while active or disabled stays quiet")
    func readyRules() {
        var notifier = ProcessingNotifier()
        #expect(notifier.decide(.stageChanged(recordingID: id, stage: .ready), appIsActive: true, enabled: true) == nil)
        var again = ProcessingNotifier()
        #expect(again.decide(.stageChanged(recordingID: id, stage: .ready), appIsActive: false, enabled: false) == nil)

        var away = ProcessingNotifier()
        let first = away.decide(.stageChanged(recordingID: id, stage: .ready), appIsActive: false, enabled: true)
        #expect(first?.kind == .summaryReady)
        #expect(first?.recordingID == id)
        #expect(away.decide(.stageChanged(recordingID: id, stage: .ready), appIsActive: false, enabled: true) == nil, "a relabel's second ready is not announced")

        // A new run of the pipeline for the same recording can announce again.
        #expect(away.decide(.stageChanged(recordingID: id, stage: .transcribing), appIsActive: false, enabled: true) == nil)
        #expect(away.decide(.stageChanged(recordingID: id, stage: .ready), appIsActive: false, enabled: true)?.kind == .summaryReady)
    }

    @Test("A failure needs attention, and the ready that follows a summary failure is not a summary")
    func failureRules() {
        var notifier = ProcessingNotifier()
        let failed = notifier.decide(.failed(recordingID: id, stage: .summarizing, message: "busy"), appIsActive: false, enabled: true)
        #expect(failed?.kind == .needsAttention)
        #expect(notifier.decide(.stageChanged(recordingID: id, stage: .ready), appIsActive: false, enabled: true) == nil)
        #expect(notifier.decide(.stageChanged(recordingID: id, stage: .ready), appIsActive: false, enabled: true) == nil, "still nothing: the failed run never became a summary")
        // Retry: a new summarizing run that finishes is a summary again.
        #expect(notifier.decide(.stageChanged(recordingID: id, stage: .summarizing), appIsActive: false, enabled: true) == nil)
        #expect(notifier.decide(.stageChanged(recordingID: id, stage: .ready), appIsActive: false, enabled: true)?.kind == .summaryReady)

        var transcription = ProcessingNotifier()
        #expect(transcription.decide(.failed(recordingID: id, stage: .transcribing, message: "x"), appIsActive: false, enabled: true)?.kind == .needsAttention)
        var active = ProcessingNotifier()
        #expect(active.decide(.failed(recordingID: id, stage: .transcribing, message: "x"), appIsActive: true, enabled: true) == nil)
    }

    @Test("Speaker-label failures are non-fatal and never notify; the summary that follows does")
    func diarizationIsNonFatal() {
        var notifier = ProcessingNotifier()
        #expect(notifier.decide(.failed(recordingID: id, stage: .diarizing, message: "no models"), appIsActive: false, enabled: true) == nil)
        #expect(notifier.decide(.stageChanged(recordingID: id, stage: .diarized), appIsActive: false, enabled: true) == nil)
        #expect(notifier.decide(.stageChanged(recordingID: id, stage: .ready), appIsActive: false, enabled: true)?.kind == .summaryReady)
    }

    @Test("Progress, downloads and recovery never notify")
    func noise() {
        var notifier = ProcessingNotifier()
        #expect(notifier.decide(.progress(recordingID: id, stage: .transcribing, fraction: 0.5), appIsActive: false, enabled: true) == nil)
        #expect(notifier.decide(.preparingAssets(recordingID: id, stage: .diarizing, fraction: 0.5), appIsActive: false, enabled: true) == nil)
        #expect(notifier.decide(.recoveredInterruptedRecording(recordingID: id), appIsActive: false, enabled: true) == nil)
        let notification = ProcessingNotification(kind: .needsAttention, recordingID: id, recordingTitle: "Kickoff")
        #expect(notification.title == "Needs attention")
        #expect(notification.identifier == "processing.\(id.uuidString)")
    }
}
