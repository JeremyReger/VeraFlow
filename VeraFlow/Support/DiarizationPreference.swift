import Foundation

/// The "Expected voices" setting (SPEC §10.3): a hint for the diarizer's clustering. The value in
/// Settings is the *default* for recordings the user hasn't answered for; a recording that carries
/// its own count (`Recording.expectedSpeakers`) uses that instead.
enum DiarizationPreference {
    enum ExpectedSpeakers: String, CaseIterable, Sendable {
        case automatic
        case two
        case three
        case fourOrMore

        var displayName: String {
            switch self {
            case .automatic: "Automatic"
            case .two: "2"
            case .three: "3"
            case .fourOrMore: "4 or more"
            }
        }

        /// The exact count to ask for, or `nil` to let the diarizer decide. "4 or more" is a
        /// minimum, so it stays automatic rather than forcing exactly four.
        var exactCount: Int? {
            switch self {
            case .automatic, .fourOrMore: nil
            case .two: 2
            case .three: 3
            }
        }

        /// A lower bound for the "4 or more" choice.
        var minimumCount: Int? {
            self == .fourOrMore ? 4 : nil
        }
    }

    static let key = "diarization.expectedSpeakers"

    /// The default for recordings that don't carry a count of their own.
    static func defaultExpectedSpeakers(in defaults: UserDefaults = .standard) -> ExpectedSpeakers {
        ExpectedSpeakers(rawValue: defaults.string(forKey: key) ?? "") ?? .automatic
    }

    static func setDefaultExpectedSpeakers(_ value: ExpectedSpeakers, in defaults: UserDefaults = .standard) {
        defaults.set(value.rawValue, forKey: key)
    }

    /// What the diarizer is told for one recording: its own count when it has one, else the default.
    static func resolved(for recording: ExpectedSpeakers?, default fallback: ExpectedSpeakers) -> ExpectedSpeakers {
        recording ?? fallback
    }
}

/// What the pipeline hands the diarizer, resolved from the preference.
struct SpeakerCountHint: Sendable, Equatable {
    var exact: Int?
    var minimum: Int?

    static let automatic = SpeakerCountHint()

    init(exact: Int? = nil, minimum: Int? = nil) {
        self.exact = exact
        self.minimum = minimum
    }

    init(_ preference: DiarizationPreference.ExpectedSpeakers) {
        self.init(exact: preference.exactCount, minimum: preference.minimumCount)
    }
}

extension SpeakerCountHint: CustomStringConvertible {
    /// For the device log, so a run that found the wrong number of speakers says what it was told.
    var description: String {
        switch (exact, minimum) {
        case (let exact?, _): "exactly \(exact)"
        case (nil, let minimum?): "\(minimum) or more"
        default: "automatic"
        }
    }
}

/// Whether to offer the speaker-count hint on a recording the diarizer heard as one voice.
///
/// Clustering can collapse to a single speaker when the voices reach the microphone through the
/// same channel — a meeting on speakerphone, a broadcast across a room — because the room and the
/// codec dominate the speaker embedding. Jeremy's 2:11 Mac recording: 60 embedding windows, one
/// centroid. The setting that fixes it already exists, so the transcript says so rather than
/// leaving a wrong answer sitting there (2026-09-19).
enum SpeakerCountNotice {
    /// Long enough that one voice for the whole recording is worth questioning. A short memo
    /// really is one person, and nagging about it would be noise.
    static let minimumDuration: TimeInterval = 45

    static func shouldOfferHint(
        speakerCount: Int,
        duration: TimeInterval,
        hint: DiarizationPreference.ExpectedSpeakers,
        isLabeled: Bool
    ) -> Bool {
        // Only once the labels have actually run, only when they found exactly one voice, and
        // only while the user hasn't already answered for *this* recording — if they said 2 and
        // still got 1, repeating the advice is no help. `hint` is the resolved count, so a
        // recording that has never been answered for is still asked even when another one was.
        guard isLabeled, speakerCount == 1, hint == .automatic else { return false }
        return duration >= minimumDuration
    }

    /// What the banner offers, in the order it offers them.
    static let choices: [DiarizationPreference.ExpectedSpeakers] = [.two, .three, .fourOrMore]
}
