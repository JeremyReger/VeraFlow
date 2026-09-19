import Foundation
import Testing
@testable import VeraFlow

struct TranscriptionLanguagesTests {
    private let english = Locale(identifier: "en")

    @Test("Follow-the-iPhone comes first, then supported locales by name, one per identifier")
    func rows() {
        let supported = [Locale(identifier: "es_ES"), Locale(identifier: "en_US"), Locale(identifier: "en-US"), Locale(identifier: "de_DE")]
        let rows = TranscriptionLanguages.options(supported: supported, device: Locale(identifier: "en_US"), chosen: nil, displayLocale: english)
        #expect(rows.map(\.identifier) == [nil, "en-US", "de-DE", "es-ES"])
        #expect(rows[0].name.hasPrefix("Follow the iPhone (English"))
        #expect(rows[0].isSelected)
        #expect(rows.dropFirst().allSatisfy { !$0.isSelected })
        #expect(rows[2].name.hasPrefix("German"))
    }

    @Test("The chosen locale is marked, whatever the identifier spelling")
    func selection() {
        let supported = [Locale(identifier: "es_ES"), Locale(identifier: "en_US")]
        let rows = TranscriptionLanguages.options(supported: supported, device: Locale(identifier: "en_US"), chosen: Locale(identifier: "es-ES"), displayLocale: english)
        #expect(rows.first { $0.identifier == "es-ES" }?.isSelected == true)
        #expect(!rows[0].isSelected)
        #expect(TranscriptionLanguages.name(for: Locale(identifier: "fr_FR"), displayLocale: english).hasPrefix("French"))
    }
}
