import Foundation

/// What the user asked for, remembered across launches.
enum AudioInputChoice: Equatable, Sendable {
    /// Nothing chosen yet: prefer the built-in microphone (SPEC §8.1, decided 2026-09-17).
    case unset
    /// Let iOS choose (with a headset connected that means the headset's call-quality mic).
    case automatic
    /// A specific port UID from `AudioInputOption.id`.
    case device(String)

    /// Stored as: absent → `.unset`, "" → `.automatic`, anything else → `.device`.
    init(stored: String?) {
        switch stored {
        case nil: self = .unset
        case "": self = .automatic
        case let id?: self = .device(id)
        }
    }

    var stored: String? {
        switch self {
        case .unset: nil
        case .automatic: ""
        case .device(let id): id
        }
    }
}

/// Turns the remembered choice plus what is plugged in right now into the port to prefer.
enum AudioInputPolicy {
    /// `nil` means "let iOS choose".
    static func effectiveInput(available: [AudioInputOption], choice: AudioInputChoice) -> String? {
        let builtIn = available.first { $0.isBuiltIn }?.id
        switch choice {
        case .automatic:
            return nil
        case .unset:
            return builtIn
        case .device(let id):
            // The chosen device is gone (headset in its case): fall back to the phone mic.
            return available.contains { $0.id == id } ? id : builtIn
        }
    }
}

/// What `setPreferredInput` should be called with once the session is active. Kept pure so the
/// timing rule (Apple: set the preferred input only after activating the session) is testable.
enum AudioInputRouting: Equatable, Sendable {
    /// The session already prefers this port (or no preference is wanted and none is set).
    case unchanged
    /// Call `setPreferredInput(nil)`: let iOS choose.
    case clear
    /// Call `setPreferredInput(port)` for this UID.
    case prefer(String)
    /// The wanted port isn't in `availableInputs` right now; leave routing alone.
    case unavailable

    static func action(wanted: String?, available: [String], sessionPreferred: String?) -> AudioInputRouting {
        guard let wanted else {
            return sessionPreferred == nil ? .unchanged : .clear
        }
        guard available.contains(wanted) else { return .unavailable }
        return sessionPreferred == wanted ? .unchanged : .prefer(wanted)
    }
}

/// What the tap is currently running against: the format it was installed with, and on the Mac
/// the Core Audio device the engine's input unit is bound to.
struct CaptureState: Equatable, Sendable {
    var sampleRate: Double
    var channels: UInt32
    /// The bound input device. Always nil on iOS, which routes through the audio session instead
    /// of binding a device to the engine.
    var deviceID: UInt32?

    init(sampleRate: Double, channels: UInt32, deviceID: UInt32? = nil) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.deviceID = deviceID
    }
}

/// Whether an `AVAudioEngineConfigurationChange` is the hardware moving or our own doing.
///
/// On the Mac, binding an input device to the engine's input unit posts a configuration change
/// itself. Answering every one of them by rebuilding the engine binds the device again, which
/// posts another: the engine restarts forever and never runs long enough to deliver a buffer,
/// which is what emptied the first Mac recordings (2026-09-19). Comparing what the tap runs
/// against with what the engine reports now tells the two apart — a real change always moves the
/// format or the device.
enum CaptureRestart: Equatable, Sendable {
    /// Something moved: discard the engine and re-tap the microphone in its new format.
    case rebuild
    /// Nothing moved. Keep the tap; the engine only needs starting again if it stopped.
    case keepTap

    static func decide(tapped: CaptureState, current: CaptureState) -> CaptureRestart {
        // Right after a route change the engine reports a format of zero for a moment. That is
        // not evidence the hardware moved, and a tap can't be installed against it either.
        guard current.sampleRate > 0, current.channels > 0 else { return .keepTap }
        return tapped == current ? .keepTap : .rebuild
    }
}
