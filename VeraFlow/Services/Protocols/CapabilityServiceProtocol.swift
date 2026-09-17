import Foundation

public struct DeviceCapabilities: Sendable {
    public var hasSpeechTranscriber: Bool
    public var hasAppleIntelligence: Bool
    public var isAppleIntelligenceDownloading: Bool
    public var isDiarizationReady: Bool
    public var supportsBackgroundProcessing: Bool
    public var estimatedTokenContextLimit: Int
    
    public var honestCapabilityMessage: String {
        if hasAppleIntelligence {
            return "This iPhone supports on-device speech transcription and local Apple Intelligence summaries."
        } else if isAppleIntelligenceDownloading {
            return "Apple Intelligence models are currently downloading on this device."
        } else {
            return "Transcripts work on this iPhone; AI summaries need an Apple Intelligence–capable iPhone."
        }
    }
    
    public init(
        hasSpeechTranscriber: Bool = true,
        hasAppleIntelligence: Bool = true,
        isAppleIntelligenceDownloading: Bool = false,
        isDiarizationReady: Bool = true,
        supportsBackgroundProcessing: Bool = true,
        estimatedTokenContextLimit: Int = 4096
    ) {
        self.hasSpeechTranscriber = hasSpeechTranscriber
        self.hasAppleIntelligence = hasAppleIntelligence
        self.isAppleIntelligenceDownloading = isAppleIntelligenceDownloading
        self.isDiarizationReady = isDiarizationReady
        self.supportsBackgroundProcessing = supportsBackgroundProcessing
        self.estimatedTokenContextLimit = estimatedTokenContextLimit
    }
}

public protocol CapabilityServiceProtocol: Sendable {
    func currentCapabilities() async -> DeviceCapabilities
    func checkSpeechLocaleAvailability(locale: Locale) async -> Bool
    func calculateStorageUsage() -> (recordingCount: Int, totalSizeBytes: Int64)
}
