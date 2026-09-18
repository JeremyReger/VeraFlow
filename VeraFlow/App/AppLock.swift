import Foundation
import LocalAuthentication
import Observation
import SwiftUI

/// Optional Face ID / passcode lock (SPEC §14.4). Locks when the app leaves the foreground and
/// asks the system to authenticate when it comes back. Devices without a passcode can't lock.
@Observable
@MainActor
final class AppLock {
    private(set) var isLocked: Bool
    private(set) var isAuthenticating = false
    private(set) var lastError: String?

    var isEnabled: Bool {
        didSet {
            AppPreferences.setAppLockEnabled(isEnabled)
            if !isEnabled { isLocked = false }
        }
    }

    init(enabled: Bool = AppPreferences.appLockEnabled()) {
        isEnabled = enabled
        isLocked = enabled
    }

    /// Whether this device can authenticate at all (Face ID, Touch ID, or a passcode).
    static var canAuthenticate: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    func lock() {
        guard isEnabled else { return }
        isLocked = true
    }

    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No passcode set: nothing to lock behind.
            isLocked = false
            return
        }
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock VeraFlow")
            isLocked = !ok
            lastError = ok ? nil : "Couldn't verify it's you."
        } catch {
            lastError = error.localizedDescription
        }
    }
}

/// Full-screen cover while the app is locked.
struct LockScreenView: View {
    let lock: AppLock

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            VFWaveformMark(height: 44)
                .accessibilityHidden(true)
            Text("VeraFlow is locked")
                .vfText(VFText.recordingTitle)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            if let error = lock.lastError {
                Text(error)
                    .vfText(VFText.snippet, color: VFColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Button(lock.isAuthenticating ? "Unlocking…" : "Unlock") {
                Task { await lock.unlock() }
            }
            .buttonStyle(VFPrimaryPillStyle())
            .disabled(lock.isAuthenticating)
            .padding(.top, 8)
            .accessibilityIdentifier("lock.unlock")
            Spacer()
            VFReassurance()
                .padding(.bottom, VFSpace.bottomInset)
        }
        .padding(.horizontal, VFSpace.gutter + 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VFColor.background.ignoresSafeArea())
        // VoiceOver stays inside the cover (A-1).
        .accessibilityAddTraits(.isModal)
        .task { await lock.unlock() }
    }
}

/// Opaque cover shown while the scene is inactive and the app lock is on, so the app-switcher
/// snapshot and any glance over the shoulder show nothing (security review S-1).
struct PrivacyShieldView: View {
    var body: some View {
        VStack(spacing: 16) {
            VFWaveformMark(height: 44)
                .accessibilityHidden(true)
            Text("VeraFlow")
                .vfText(VFText.cardTitle)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VFColor.background.ignoresSafeArea())
        .accessibilityAddTraits(.isModal)
    }
}
