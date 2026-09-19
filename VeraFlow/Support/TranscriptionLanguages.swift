import Foundation

/// One row of the transcription-language picker (v1.1 plan item 8).
struct LanguageOption: Equatable, Sendable, Identifiable {
    /// BCP-47, or `nil` for "follow the iPhone".
    var identifier: String?
    var name: String
    var isSelected: Bool

    var id: String { identifier ?? "device" }
}

/// Builds the picker rows from what the speech engine supports. Pure, so it's unit-tested.
enum TranscriptionLanguages {
    /// "Follow the iPhone (English (US))" first, then every supported locale by name, one row
    /// per BCP-47 identifier. `chosen` is the stored preference (`nil` = follow the iPhone).
    static func options(supported: [Locale], device: Locale, chosen: Locale?, displayLocale: Locale = .current) -> [LanguageOption] {
        let chosenID = chosen?.identifier(.bcp47)
        var seen = Set<String>()
        var rows: [LanguageOption] = []
        for locale in supported {
            let identifier = locale.identifier(.bcp47)
            guard seen.insert(identifier).inserted else { continue }
            rows.append(LanguageOption(identifier: identifier, name: name(for: locale, displayLocale: displayLocale), isSelected: identifier == chosenID))
        }
        rows.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let deviceRow = LanguageOption(
            identifier: nil,
            name: "Follow the iPhone (\(name(for: device, displayLocale: displayLocale)))",
            isSelected: chosenID == nil
        )
        return [deviceRow] + rows
    }

    /// "English (United States)" in the display locale, falling back to the identifier.
    static func name(for locale: Locale, displayLocale: Locale = .current) -> String {
        let identifier = locale.identifier(.bcp47)
        return displayLocale.localizedString(forIdentifier: identifier) ?? identifier
    }
}
