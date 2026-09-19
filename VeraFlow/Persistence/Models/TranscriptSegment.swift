import Foundation
import SwiftData

/// One speaker turn / paragraph of the transcript (SPEC §7).
@Model
final class TranscriptSegment {
    var index: Int
    var start: TimeInterval
    var end: TimeInterval
    /// User-editable text.
    var text: String
    /// Text exactly as transcribed.
    var originalText: String
    /// Speaker key such as "S1"; `nil` before diarization.
    var speakerKey: String?
    /// Encoded `[TimedWord]` used for playback highlight and tap-to-seek.
    var wordsData: Data?
    /// v1.1: this paragraph in another language (plan item 14); `nil` until translated.
    var translatedText: String?
    /// v1.1: BCP-47 identifier of the language `translatedText` is in.
    var translationLanguage: String?

    var recording: Recording?

    init(
        index: Int,
        start: TimeInterval,
        end: TimeInterval,
        text: String,
        originalText: String? = nil,
        speakerKey: String? = nil,
        words: [TimedWord] = []
    ) {
        self.index = index
        self.start = start
        self.end = end
        self.text = text
        self.originalText = originalText ?? text
        self.speakerKey = speakerKey
        self.wordsData = try? words.encoded()
    }

    /// Decoded words; empty if none were stored.
    var words: [TimedWord] {
        (try? [TimedWord].decoded(from: wordsData)) ?? []
    }

    /// True if the user changed the text after transcription.
    var isEdited: Bool { text != originalText }

    /// The translation, if it is in `language`.
    func translation(in language: String) -> String? {
        guard translationLanguage == language else { return nil }
        return translatedText
    }
}
