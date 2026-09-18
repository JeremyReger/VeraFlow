import Foundation

/// Small user settings that live in `UserDefaults` (SPEC §4.1, §14.2, §14.4).
enum AppPreferences {
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

    /// The summary template offered on the Record screen (design spec §4 Record — ready). The
    /// last choice is remembered; General until then.
    static func defaultTemplate(in defaults: UserDefaults = .standard) -> TemplateID {
        defaults.string(forKey: defaultTemplateKey).flatMap(TemplateID.init(rawValue:)) ?? .general
    }

    static func setDefaultTemplate(_ template: TemplateID, in defaults: UserDefaults = .standard) {
        defaults.set(template.rawValue, forKey: defaultTemplateKey)
    }
}
