import Foundation
import SwiftUI

/// Light, dark, or follow the system (Settings → Appearance). Stored by raw value.
enum Appearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// `nil` lets the system decide.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Small user settings that live in `UserDefaults` (SPEC §4.1, §14.2, §14.4).
enum AppPreferences {
    static let appearanceKey = "display.appearance"

    static let onboardingCompletedKey = "onboarding.completed"
    static let consentReminderKey = "recording.consentReminder"
    static let appLockKey = "privacy.appLock"
    static let diagnosticsUnlockedKey = "diagnostics.unlocked"
    static let defaultTemplateKey = "recording.defaultTemplate"

    static func onboardingCompleted(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: onboardingCompletedKey)
    }

    static func setOnboardingCompleted(_ value: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: onboardingCompletedKey)
    }

    /// The pre-record consent reminder (SPEC §14.2). On by default.
    static func showsConsentReminder(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: consentReminderKey) as? Bool ?? true
    }

    static func setShowsConsentReminder(_ value: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: consentReminderKey)
    }

    /// Face ID / passcode lock for the app (SPEC §14.4). Off by default.
    static func appLockEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: appLockKey)
    }

    static func setAppLockEnabled(_ value: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: appLockKey)
    }

    /// The hidden Diagnostics screen (SPEC §15) stays reachable once unlocked by 7 taps on the version.
    static func diagnosticsUnlocked(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: diagnosticsUnlockedKey)
    }

    static func setDiagnosticsUnlocked(_ value: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: diagnosticsUnlockedKey)
    }

    static func appearance(in defaults: UserDefaults = .standard) -> Appearance {
        defaults.string(forKey: appearanceKey).flatMap(Appearance.init(rawValue:)) ?? .system
    }

    static func setAppearance(_ appearance: Appearance, in defaults: UserDefaults = .standard) {
        defaults.set(appearance.rawValue, forKey: appearanceKey)
    }

    /// The summary template offered on the Record screen (design spec §4 Record — ready). The
    /// last choice is remembered; General until then.
    static func defaultTemplate(in defaults: UserDefaults = .standard) -> TemplateID {
        defaults.string(forKey: defaultTemplateKey).flatMap(TemplateID.init(rawValue:)) ?? .general
    }

    static func setDefaultTemplate(_ template: TemplateID, in defaults: UserDefaults = .standard) {
        defaults.set(template.rawValue, forKey: defaultTemplateKey)
    }
}
