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
}
