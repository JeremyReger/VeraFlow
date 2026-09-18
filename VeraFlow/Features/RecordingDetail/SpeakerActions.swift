import Foundation
import SwiftData
import SwiftUI

/// Rename, merge, and reassign speakers on one recording (SPEC §10.3). Summaries reference
/// speakers by key, so renaming here updates everywhere at render time.
struct SpeakerActions {
    let context: ModelContext

    enum ActionError: Error, Equatable {
        case emptyName
    }

    func rename(_ speaker: Speaker, to name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ActionError.emptyName }
        speaker.displayName = trimmed
        try context.save()
    }

    /// Moves every paragraph of `source` to `target` and removes `source` (SPEC §10.3 "Merge speakers").
    func merge(_ source: Speaker, into target: Speaker, in recording: Recording) throws {
        guard source.key != target.key else { return }
        for segment in recording.segments where segment.speakerKey == source.key {
            segment.speakerKey = target.key
        }
        recording.speakers.removeAll { $0.key == source.key }
        context.delete(source)
        try context.save()
    }

    /// "Change speaker for this paragraph."
    func assign(_ segment: TranscriptSegment, to speaker: Speaker) throws {
        segment.speakerKey = speaker.key
        try context.save()
    }

    /// Adds "Speaker n" with the next free key and puts `segment` on it.
    @discardableResult
    func assignToNewSpeaker(_ segment: TranscriptSegment, in recording: Recording) throws -> Speaker {
        let speaker = Self.nextSpeaker(for: recording)
        recording.speakers.append(speaker)
        segment.speakerKey = speaker.key
        try context.save()
        return speaker
    }

    /// The next unused `S<n>` on this recording.
    static func nextSpeaker(for recording: Recording) -> Speaker {
        let used = Set(recording.speakers.map(\.key))
        var number = recording.speakers.count + 1
        while used.contains("S\(number)") {
            number += 1
        }
        return Speaker.default(number: number)
    }
}

/// Presentation state for the speaker alerts, shared by the transcript header and paragraphs.
@Observable
@MainActor
final class SpeakerActionsController {
    var renameTarget: Speaker?
    var renameDraft = ""
    var errorMessage: String?

    let actions: SpeakerActions

    init(actions: SpeakerActions) {
        self.actions = actions
    }

    func beginRename(_ speaker: Speaker) {
        renameDraft = speaker.displayName
        renameTarget = speaker
    }

    /// Takes the speaker explicitly: the alert is already dismissed (and `renameTarget` cleared)
    /// when SwiftUI runs the Save action.
    func commitRename(_ speaker: Speaker) {
        renameTarget = nil
        do {
            try actions.rename(speaker, to: renameDraft)
        } catch SpeakerActions.ActionError.emptyName {
            errorMessage = "A speaker needs a name."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancelRename() {
        renameTarget = nil
    }

    func merge(_ source: Speaker, into target: Speaker, in recording: Recording) {
        do {
            try actions.merge(source, into: target, in: recording)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func assign(_ segment: TranscriptSegment, to speaker: Speaker) {
        do {
            try actions.assign(segment, to: speaker)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func assignToNewSpeaker(_ segment: TranscriptSegment, in recording: Recording) {
        do {
            try actions.assignToNewSpeaker(segment, in: recording)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Speaker label colours, indexed by `Speaker.colorIndex`: the design tokens' five pairs,
/// authored per appearance for at least 4.5:1 on their ground (design spec §2, review A-7).
enum SpeakerPalette {
    static func color(for index: Int) -> Color {
        VFColor.speaker(index)
    }
}
