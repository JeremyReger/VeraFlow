import Foundation
import LocalAuthentication

/// Service managing Face ID / Touch ID authentication to secure recording archives (§14.4).
public final class BiometricLockService: Sendable {
    
    public init() {}
    
    public enum BiometryType: String, Sendable {
        case faceID = "Face ID"
        case touchID = "Touch ID"
        case none = "None"
    }
    
    public func biometryType() -> BiometryType {
        let context = LAContext()
        var error: NSError?
        
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            switch context.biometryType {
            case .faceID:
                return .faceID
            case .touchID:
                return .touchID
            default:
                return .none
            }
        }
        return .none
    }
    
    public func canAuthenticate() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
    
    public func authenticate(reason: String = "Unlock VeraFlow to access your private recordings.") async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // If biometrics not available, allow pass in simulator or fallback
            #if targetEnvironment(simulator)
            return true
            #else
            return false
            #endif
        }
        
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}
