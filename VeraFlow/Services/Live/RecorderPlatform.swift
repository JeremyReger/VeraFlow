import AVFAudio
import Foundation
import os
#if os(macOS)
import AudioToolbox
import CoreAudio
#endif

/// What the system said about the capture session. Only iOS has a session; the Mac never
/// emits these, and its device changes arrive as `AVAudioEngineConfigurationChange` instead.
enum RecorderSessionEvent: Sendable {
    case interruptionBegan(reason: String)
    case interruptionEnded(shouldResume: Bool)
    case mediaServicesReset
    case routeChanged(oldDeviceUnavailable: Bool)
}

/// The platform half of `LiveAudioRecorderService` (v1.1 plan item 15). On iOS this is
/// `AVAudioSession`: category and activation, the input list, the preferred input, and the
/// interruption / route notifications. On the Mac there is no audio session: inputs come from
/// Core Audio and the chosen device is set on the engine's input unit before the tap goes in.
/// The recorder's control flow (restart on configuration change, pause without stopping the
/// engine, the settle loops) is the same on both and stays in the actor.
enum RecorderPlatform {
    private static let log = Logger(subsystem: "com.jeremyreger.veraflow", category: "recorder-platform")

    /// Where a new input takes effect only after the engine is rebuilt. iOS re-taps on its own
    /// through the configuration-change notification once the route follows the preference.
    #if os(macOS)
    static let inputChangeNeedsRestart = true
    #else
    static let inputChangeNeedsRestart = false
    #endif

    #if os(iOS)

    // MARK: iOS — AVAudioSession

    private static var session: AVAudioSession { AVAudioSession.sharedInstance() }

    /// Sets the record category and activates the session.
    static func activate() throws {
        try configure()
        try session.setActive(true)
    }

    static func deactivate() {
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Inputs are only listed for record-capable categories. Called while idle so the list is
    /// right before the first recording; never re-sets the category while capture is running.
    static func configureForInputListing() {
        try? configure()
    }

    private static func configure() throws {
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.allowBluetoothHFP, .defaultToSpeaker]
        )
    }

    static func availableInputs() -> [AudioInputOption] {
        (session.availableInputs ?? []).map { port in
            AudioInputOption(id: port.uid, name: port.portName, isBuiltIn: port.portType == .builtInMic)
        }
    }

    /// The session's current preference. `applied` is what the Mac tracks instead; unused here.
    static func preferredInputID(applied: String?) -> String? {
        session.preferredInput?.uid
    }

    /// `nil` clears the preference. A port that isn't listed right now is simply not applied.
    static func setPreferredInput(_ id: String?) throws {
        guard let id else {
            try session.setPreferredInput(nil)
            return
        }
        if let port = session.availableInputs?.first(where: { $0.uid == id }) {
            try session.setPreferredInput(port)
        }
    }

    /// The route change is asynchronous; waits up to a second for the input to appear in it.
    static func waitForRoute(input id: String) async {
        for _ in 0..<10 where !session.currentRoute.inputs.contains(where: { $0.uid == id }) {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    static var routeDescription: String {
        let inputs = session.currentRoute.inputs.map(\.portName).joined(separator: ",")
        let outputs = session.currentRoute.outputs.map(\.portName).joined(separator: ",")
        return "\(inputs) -> \(outputs)"
    }

    /// iOS picks the input from the session's preference; nothing to set on the engine.
    static func applyInput(_ id: String?, to engine: AVAudioEngine) throws {}

    /// Interruption, media-reset and route-change notifications, parsed into `RecorderSessionEvent`.
    static func observeSession(_ handler: @escaping @Sendable (RecorderSessionEvent) -> Void) -> [any NSObjectProtocol] {
        let center = NotificationCenter.default
        let session = self.session
        var observers: [any NSObjectProtocol] = []
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: nil) { notification in
            guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
            switch type {
            case .began:
                let rawReason = notification.userInfo?[AVAudioSessionInterruptionReasonKey] as? UInt
                handler(.interruptionBegan(reason: describeInterruptionReason(rawReason)))
            case .ended:
                let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let shouldResume = AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume)
                handler(.interruptionEnded(shouldResume: shouldResume))
            @unknown default:
                break
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: nil) { _ in
            handler(.mediaServicesReset)
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: nil) { notification in
            guard let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason) else { return }
            handler(.routeChanged(oldDeviceUnavailable: reason == .oldDeviceUnavailable))
        })
        return observers
    }

    /// Why the system interrupted us, for the device log (SPEC §8.3 troubleshooting).
    private static func describeInterruptionReason(_ rawReason: UInt?) -> String {
        guard let rawReason else { return "none" }
        switch AVAudioSession.InterruptionReason(rawValue: rawReason) {
        case .default?: return "default (call, alarm, Siri, or another app)"
        case .builtInMicMuted?: return "built-in mic muted"
        case .routeDisconnected?: return "route disconnected"
        default: return "raw \(rawReason)"
        }
    }

    /// Fires whenever a headset connects or disconnects; the Record screen reloads its list.
    static func inputListChanges() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let token = ObserverToken(NotificationCenter.default.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: nil,
                queue: nil
            ) { _ in
                continuation.yield()
            })
            continuation.onTermination = { _ in
                NotificationCenter.default.removeObserver(token.value)
            }
        }
    }

    private final class ObserverToken: @unchecked Sendable {
        let value: any NSObjectProtocol
        init(_ value: any NSObjectProtocol) { self.value = value }
    }

    #elseif os(macOS)

    // MARK: macOS — Core Audio devices, no session

    static func activate() throws {}
    static func deactivate() {}
    static func configureForInputListing() {}

    static func availableInputs() -> [AudioInputOption] {
        MacAudioInputs.devices()
    }

    /// The Mac has no session preference: the input the engine was last built with counts.
    static func preferredInputID(applied: String?) -> String? {
        applied
    }

    /// Nothing to set ahead of time; `applyInput(_:to:)` binds the device to the engine.
    static func setPreferredInput(_ id: String?) throws {}

    static func waitForRoute(input id: String) async {}

    static var routeDescription: String {
        MacAudioInputs.defaultInputName() ?? "default input"
    }

    /// Binds the chosen device to the engine's input unit; `nil` keeps the system default.
    /// Must run before the input format is read and the tap is installed.
    static func applyInput(_ id: String?, to engine: AVAudioEngine) throws {
        guard let id, let deviceID = MacAudioInputs.deviceID(forUID: id) else { return }
        guard let unit = engine.inputNode.audioUnit else {
            throw AudioRecorderError.sessionFailed("The audio engine has no input unit")
        }
        var device = deviceID
        let status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &device,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw AudioRecorderError.sessionFailed("Could not select that microphone (Core Audio error \(status))")
        }
        log.info("input device \(id, privacy: .public) bound to the engine")
    }

    /// No session events on the Mac; device changes reach the actor as engine configuration changes.
    static func observeSession(_ handler: @escaping @Sendable (RecorderSessionEvent) -> Void) -> [any NSObjectProtocol] {
        []
    }

    static func inputListChanges() -> AsyncStream<Void> {
        MacAudioInputs.deviceListChanges()
    }

    #endif
}

#if os(macOS)
/// Core Audio's input devices, for the microphone menu and the engine binding above.
enum MacAudioInputs {
    /// Every device with at least one input channel, built-in first.
    static func devices() -> [AudioInputOption] {
        deviceIDs().compactMap { device -> AudioInputOption? in
            guard inputChannelCount(of: device) > 0,
                  let uid = string(kAudioDevicePropertyDeviceUID, of: device) else { return nil }
            let name = string(kAudioObjectPropertyName, of: device) ?? uid
            let transport = uint32(kAudioDevicePropertyTransportType, of: device)
            return AudioInputOption(id: uid, name: name, isBuiltIn: transport == kAudioDeviceTransportTypeBuiltIn)
        }
        .sorted { a, b in
            if a.isBuiltIn != b.isBuiltIn { return a.isBuiltIn }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        deviceIDs().first { string(kAudioDevicePropertyDeviceUID, of: $0) == uid }
    }

    static func defaultInputName() -> String? {
        guard let device = uint32(kAudioHardwarePropertyDefaultInputDevice, of: AudioObjectID(kAudioObjectSystemObject)) else { return nil }
        return string(kAudioObjectPropertyName, of: AudioDeviceID(device))
    }

    /// Yields whenever the device list changes (a USB microphone plugged in or pulled).
    static func deviceListChanges() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let listener = Listener { continuation.yield() }
            var address = devicesAddress
            let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, listener.block)
            guard status == noErr else {
                continuation.finish()
                return
            }
            continuation.onTermination = { _ in
                var address = devicesAddress
                AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, listener.block)
            }
        }
    }

    private final class Listener: @unchecked Sendable {
        let block: AudioObjectPropertyListenerBlock
        init(_ fire: @escaping @Sendable () -> Void) {
            block = { _, _ in fire() }
        }
    }

    private static var devicesAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func deviceIDs() -> [AudioDeviceID] {
        var address = devicesAddress
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func inputChannelCount(of device: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = raw.assumingMemoryBound(to: AudioBufferList.self)
        return UnsafeMutableAudioBufferListPointer(list).reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func string(_ selector: AudioObjectPropertySelector, of object: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func uint32(_ selector: AudioObjectPropertySelector, of object: AudioObjectID) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }
}
#endif
