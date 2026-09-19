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
    // v1.1
    static let transcriptionLocaleKey = "recording.transcriptionLocale"
    static let skipSilenceKey = "playback.skipSilence"
    static let notifySummaryReadyKey = "notifications.summaryReady"
    static let includeInBackupKey = "storage.includeInBackup"
    static let sampleSeededKey = "sample.seeded"
    static let defaultCustomTemplateKey = "recording.defaultCustomTemplate"

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

    // MARK: v1.1

    /// BCP-47 identifier of the language new recordings are transcribed in; `nil` follows the
    /// iPhone's language (plan item 8).
    static func transcriptionLocale(in defaults: UserDefaults = .standard) -> Locale? {
        guard let identifier = defaults.string(forKey: transcriptionLocaleKey), !identifier.isEmpty else { return nil }
        return Locale(identifier: identifier)
    }

    static func setTranscriptionLocale(_ locale: Locale?, in defaults: UserDefaults = .standard) {
        defaults.set(locale?.identifier(.bcp47), forKey: transcriptionLocaleKey)
    }

    /// The locale a new recording is transcribed in: the chosen one, else the device's.
    static func effectiveTranscriptionLocale(in defaults: UserDefaults = .standard, current: Locale = .current) -> Locale {
        transcriptionLocale(in: defaults) ?? current
    }

    /// Playback jumps over pauses (plan item 9). Off by default.
    static func skipsSilence(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: skipSilenceKey)
    }

    static func setSkipsSilence(_ value: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: skipSilenceKey)
    }

    /// "Notify when a summary is ready" (plan item 6). On by default; notifications are
    /// provisional (quiet) until the user promotes them.
    static func notifiesWhenSummaryReady(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: notifySummaryReadyKey) as? Bool ?? true
    }

    static func setNotifiesWhenSummaryReady(_ value: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: notifySummaryReadyKey)
    }

    /// "Include recordings in iPhone backup" (SPEC §6.2, plan item 5). Off by default: nothing
    /// leaves the phone unless the user says so.
    static func includesRecordingsInBackup(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: includeInBackupKey)
    }

    static func setIncludesRecordingsInBackup(_ value: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: includeInBackupKey)
    }

    /// The custom template last picked on the Record screen (plan item 13); `nil` = a built-in.
    static func defaultCustomTemplateID(in defaults: UserDefaults = .standard) -> UUID? {
        defaults.string(forKey: defaultCustomTemplateKey).flatMap(UUID.init(uuidString:))
    }

    static func setDefaultCustomTemplateID(_ id: UUID?, in defaults: UserDefaults = .standard) {
        defaults.set(id?.uuidString, forKey: defaultCustomTemplateKey)
    }

    /// Alpha builds add the sample recording on first launch (plan item 7); once only.
    static func sampleSeeded(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: sampleSeededKey)
    }

    static func setSampleSeeded(_ value: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: sampleSeededKey)
    }
}
