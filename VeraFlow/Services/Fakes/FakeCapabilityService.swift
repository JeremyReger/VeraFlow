import Foundation

public final class FakeCapabilityService: CapabilityServiceProtocol, Sendable {
    private let capabilities: DeviceCapabilities
    
    public init(capabilities: DeviceCapabilities = DeviceCapabilities()) {
        self.capabilities = capabilities
    }
    
    public func currentCapabilities() async -> DeviceCapabilities {
        return capabilities
    }
    
    public func checkSpeechLocaleAvailability(locale: Locale) async -> Bool {
        return true
    }
    
    public func calculateStorageUsage() -> (recordingCount: Int, totalSizeBytes: Int64) {
        return (recordingCount: 3, totalSizeBytes: 15_420_000)
    }
}
