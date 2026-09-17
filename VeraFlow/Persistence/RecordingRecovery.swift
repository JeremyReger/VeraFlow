import Foundation
import SwiftData

/// What launch recovery found (SPEC §8.2).
struct RecordingRecoveryOutcome: Equatable, Sendable {
    /// Recordings whose audio file was readable; now `.recorded` with the duration read from the file.
    var recoveredIDs: [UUID] = []
    /// Recordings whose audio file was missing or unreadable; now `.failed`.
    var unrecoverableIDs: [UUID] = []

    var isEmpty: Bool { recoveredIDs.isEmpty && unrecoverableIDs.isEmpty }

    /// Copy for the launch alert, or `nil` when nothing was recovered.
    var userMessage: String? {
        switch (recoveredIDs.count, unrecoverableIDs.count) {
        case (0, 0):
            return nil
        case (1, 0):
            return "Recovered an interrupted recording. It's ready in your Library."
        case (let recovered, 0):
            return "Recovered \(recovered) interrupted recordings. They're ready in your Library."
        case (0, _):
            return "A recording was interrupted and its audio could not be recovered."
        default:
            return "Recovered an interrupted recording. Another could not be recovered."
        }
    }
}

/// Repairs recordings left in the `.recording` stage by a crash or force-quit (SPEC §8.2).
/// Runs on launch before the pipeline resumes.
@MainActor
struct RecordingRecovery {
    static let unrecoverableMessage = "Recording was interrupted and the audio could not be recovered."

    let context: ModelContext
    let storage: RecordingStorage

    /// Reads a file's duration; injectable so tests don't need real audio.
    var durationReader: (URL) throws -> TimeInterval = AudioFileInfo.duration(of:)

    @discardableResult
    func run() throws -> RecordingRecoveryOutcome {
        let interrupted = try context.fetch(FetchDescriptor<Recording>()).filter { $0.stage == .recording }
        var outcome = RecordingRecoveryOutcome()
        for recording in interrupted {
            let url = storage.audioURL(for: recording.id, fileName: recording.audioFileName)
            if let duration = try? durationReader(url), duration > 0 {
                recording.duration = duration
                recording.stage = .recorded
                recording.failureMessage = nil
                outcome.recoveredIDs.append(recording.id)
            } else {
                recording.stage = .failed
                recording.failureMessage = Self.unrecoverableMessage
                outcome.unrecoverableIDs.append(recording.id)
            }
        }
        if !outcome.isEmpty {
            try context.save()
        }
        return outcome
    }
}
