import Foundation
import Testing
@testable import VeraFlow

struct AppPreferencesTests {
    @Test("Defaults: onboarding not done, consent reminder on, app lock off, diagnostics hidden; all round-trip")
    func roundTrip() throws {
        let suite = "AppPreferencesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(!AppPreferences.onboardingCompleted(in: defaults))
        #expect(AppPreferences.showsConsentReminder(in: defaults))
        #expect(!AppPreferences.appLockEnabled(in: defaults))
        #expect(!AppPreferences.diagnosticsUnlocked(in: defaults))

        AppPreferences.setOnboardingCompleted(true, in: defaults)
        AppPreferences.setShowsConsentReminder(false, in: defaults)
        AppPreferences.setAppLockEnabled(true, in: defaults)
        AppPreferences.setDiagnosticsUnlocked(true, in: defaults)

        #expect(AppPreferences.onboardingCompleted(in: defaults))
        #expect(!AppPreferences.showsConsentReminder(in: defaults))
        #expect(AppPreferences.appLockEnabled(in: defaults))
        #expect(AppPreferences.diagnosticsUnlocked(in: defaults))
    }

    @Test("Appearance follows the system until chosen; junk falls back to system")
    func appearance() throws {
        let suite = "AppPreferencesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(AppPreferences.appearance(in: defaults) == .system)
        #expect(Appearance.system.colorScheme == nil)
        AppPreferences.setAppearance(.dark, in: defaults)
        #expect(AppPreferences.appearance(in: defaults) == .dark)
        #expect(Appearance.dark.colorScheme == .dark)
        defaults.set("sepia", forKey: AppPreferences.appearanceKey)
        #expect(AppPreferences.appearance(in: defaults) == .system)
    }

    @Test("Default template is General until chosen, then remembered; junk falls back to General")
    func defaultTemplate() throws {
        let suite = "AppPreferencesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(AppPreferences.defaultTemplate(in: defaults) == .general)
        AppPreferences.setDefaultTemplate(.walkthrough, in: defaults)
        #expect(AppPreferences.defaultTemplate(in: defaults) == .walkthrough)
        defaults.set("not-a-template", forKey: AppPreferences.defaultTemplateKey)
        #expect(AppPreferences.defaultTemplate(in: defaults) == .general)
    }

    @Test("v1.1 preferences: language follows the device, skip silence off, notifications on, backup off")
    func v11Defaults() throws {
        let suite = "AppPreferencesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(AppPreferences.transcriptionLocale(in: defaults) == nil)
        let device = Locale(identifier: "en_US")
        #expect(AppPreferences.effectiveTranscriptionLocale(in: defaults, current: device).identifier(.bcp47) == "en-US")
        AppPreferences.setTranscriptionLocale(Locale(identifier: "es_ES"), in: defaults)
        #expect(AppPreferences.transcriptionLocale(in: defaults)?.identifier(.bcp47) == "es-ES")
        #expect(AppPreferences.effectiveTranscriptionLocale(in: defaults, current: device).identifier(.bcp47) == "es-ES")
        AppPreferences.setTranscriptionLocale(nil, in: defaults)
        #expect(AppPreferences.transcriptionLocale(in: defaults) == nil)

        #expect(!AppPreferences.skipsSilence(in: defaults))
        AppPreferences.setSkipsSilence(true, in: defaults)
        #expect(AppPreferences.skipsSilence(in: defaults))

        #expect(AppPreferences.notifiesWhenSummaryReady(in: defaults))
        AppPreferences.setNotifiesWhenSummaryReady(false, in: defaults)
        #expect(!AppPreferences.notifiesWhenSummaryReady(in: defaults))

        #expect(!AppPreferences.includesRecordingsInBackup(in: defaults))
        AppPreferences.setIncludesRecordingsInBackup(true, in: defaults)
        #expect(AppPreferences.includesRecordingsInBackup(in: defaults))
    }
}
