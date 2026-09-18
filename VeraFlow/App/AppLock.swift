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
            Image(systemName: "lock.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("VeraFlow is locked")
                .font(.title2.bold())
            if let error = lock.lastError {
                Text(error).font(.footnote).foregroundStyle(.secondary)
            }
            Button(lock.isAuthenticating ? "Unlocking…" : "Unlock") {
                Task { await lock.unlock() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(lock.isAuthenticating)
            .accessibilityIdentifier("lock.unlock")
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .task { await lock.unlock() }
    }
}
