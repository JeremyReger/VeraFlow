import Foundation

/// The "Expected number of speakers" setting (SPEC §10.3): a hint for the diarizer's clustering.
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

    static func expectedSpeakers(in defaults: UserDefaults = .standard) -> ExpectedSpeakers {
        ExpectedSpeakers(rawValue: defaults.string(forKey: key) ?? "") ?? .automatic
    }

    static func setExpectedSpeakers(_ value: ExpectedSpeakers, in defaults: UserDefaults = .standard) {
        defaults.set(value.rawValue, forKey: key)
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
