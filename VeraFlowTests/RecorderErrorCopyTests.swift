import Foundation
import Testing
@testable import VeraFlow

/// What the Record screen says when capture fails. The wording is the whole point of these
/// cases, so it is asserted here rather than left to the device pass.
@MainActor
struct RecorderErrorCopyTests {
    @Test("Every recorder failure gets its own sentence, and none of them leaks an error code alone")
    func everyCase() {
        let cases: [AudioRecorderError] = [
            .permissionDenied,
            .alreadyRecording,
            .notRecording,
            .diskFull,
            .sessionFailed("the engine would not start"),
            .noAudioCaptured(nil),
        ]
        var seen: Set<String> = []
        for error in cases {
            let message = RecorderViewModel.message(for: error)
            #expect(message.count > 20, "too terse: \(message)")
            #expect(seen.insert(message).inserted, "two failures share one message: \(message)")
        }
    }

    @Test("An empty recording says the recording is empty, and names the file's own reason when there is one")
    func noAudioCaptured() {
        let silent = RecorderViewModel.message(for: AudioRecorderError.noAudioCaptured(nil))
        #expect(silent.contains("No audio was captured"))
        #expect(!silent.contains("("))

        let rejected = RecorderViewModel.message(for: AudioRecorderError.noAudioCaptured("The operation couldn't be completed."))
        #expect(rejected.contains("No audio was captured"))
        #expect(rejected.contains("The operation couldn't be completed."))
    }

    @Test("The microphone message sends the user to the right app for this platform")
    func microphonePane() {
        let message = RecorderViewModel.message(for: AudioRecorderError.permissionDenied)
        #expect(message.contains(Platform.settingsAppName))
    }

    @Test("An unknown error falls back to the system's own description")
    func unknown() {
        let error = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Something else went wrong."])
        #expect(RecorderViewModel.message(for: error) == "Something else went wrong.")
    }
}
