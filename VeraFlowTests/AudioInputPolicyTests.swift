import Foundation
import Testing
@testable import VeraFlow

struct AudioInputPolicyTests {
    private let phone = AudioInputOption(id: "builtin", name: "iPhone Microphone", isBuiltIn: true)
    private let buds = AudioInputOption(id: "buds", name: "Earbuds", isBuiltIn: false)

    @Test("No choice yet prefers the built-in mic even with a headset connected")
    func unsetPrefersBuiltIn() {
        #expect(AudioInputPolicy.effectiveInput(available: [buds, phone], choice: .unset) == "builtin")
        #expect(AudioInputPolicy.effectiveInput(available: [buds], choice: .unset) == nil)
    }

    @Test("Automatic always defers to iOS")
    func automatic() {
        #expect(AudioInputPolicy.effectiveInput(available: [buds, phone], choice: .automatic) == nil)
    }

    @Test("A chosen device is used when present and falls back to the phone when not")
    func device() {
        #expect(AudioInputPolicy.effectiveInput(available: [buds, phone], choice: .device("buds")) == "buds")
        #expect(AudioInputPolicy.effectiveInput(available: [phone], choice: .device("buds")) == "builtin")
        #expect(AudioInputPolicy.effectiveInput(available: [], choice: .device("buds")) == nil)
    }

    @Test("Choice round-trips through its stored form")
    func storage() {
        #expect(AudioInputChoice(stored: nil) == .unset)
        #expect(AudioInputChoice(stored: "") == .automatic)
        #expect(AudioInputChoice(stored: "abc") == .device("abc"))
        for choice in [AudioInputChoice.unset, .automatic, .device("x")] {
            #expect(AudioInputChoice(stored: choice.stored) == choice)
        }
    }
}
