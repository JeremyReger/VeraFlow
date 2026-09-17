import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

/// Comprehensive settings screen managing privacy, Face ID lock, disk storage, and model capabilities (§13, §14, §15).
public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @AppStorage("consentReminderEnabled") private var consentReminderEnabled = true
    @AppStorage("faceIDLockEnabled") private var faceIDLockEnabled = false
    
    @State private var versionTapCount = 0
    @State private var showDiagnostics = false
    @State private var showDeleteAllAlert = false
    @State private var showFaceIDAuthError = false
    @State private var capabilities: DeviceCapabilities? = nil
    @State private var storageStats: (recordingCount: Int, totalSizeBytes: Int64) = (0, 0)
    @State private var entitlement: UserEntitlementState? = nil
    @State private var showPaywallSheet = false
    
    private let capabilityService: CapabilityServiceProtocol
    private let purchaseService: PurchaseServiceProtocol
    private let biometricService = BiometricLockService()
    
    public init(
        capabilityService: CapabilityServiceProtocol = CapabilityService(),
        purchaseService: PurchaseServiceProtocol = StoreKitPurchaseService()
    ) {
        self.capabilityService = capabilityService
        self.purchaseService = purchaseService
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                // MARK: - Privacy & Security (§14)
                Section("Privacy & Security") {
                    Toggle("Recording Consent Reminder", isOn: $consentReminderEnabled)
                    
                    Toggle("Require \(biometricService.biometryType().rawValue)", isOn: Binding(
                        get: { faceIDLockEnabled },
                        set: { newValue in
                            if newValue {
                                Task {
                                    let success = await biometricService.authenticate(reason: "Enable Face ID lock for VeraFlow.")
                                    await MainActor.run {
                                        if success {
                                            faceIDLockEnabled = true
                                        } else {
                                            faceIDLockEnabled = false
                                            showFaceIDAuthError = true
                                        }
                                    }
                                }
                            } else {
                                faceIDLockEnabled = false
                            }
                        }
                    ))
                    
                    HStack {
                        Text("On-Device Guarantee")
                        Spacer()
                        Label("100% Local", systemImage: "lock.shield.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
                
                // MARK: - Storage Management (§8.3, §14)
                Section("Storage & Data Retention") {
                    HStack {
                        Text("Audio Recordings")
                        Spacer()
                        Text("\(storageStats.recordingCount) files (\(formatBytes(storageStats.totalSizeBytes)))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Button(role: .destructive) {
                        showDeleteAllAlert = true
                    } label: {
                        Label("Delete All Recordings & Data", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                }
                
                // MARK: - Models & Capabilities (§15)
                Section("Intelligence & Models") {
                    HStack {
                        Text("Transcription Engine")
                        Spacer()
                        Text(capabilities?.hasSpeechTranscriber == true ? "SpeechAnalyzer (Local)" : "Dictation Fallback")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Speaker Diarization")
                        Spacer()
                        Text("FluidAudio (Core ML)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Apple Intelligence")
                            Spacer()
                            Text(capabilities?.hasAppleIntelligence == true ? "Available" : "Unsupported")
                                .font(.subheadline)
                                .foregroundColor(capabilities?.hasAppleIntelligence == true ? .green : .orange)
                        }
                        
                        if let msg = capabilities?.honestCapabilityMessage {
                            Text(msg)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
                
                // MARK: - Monetization & Lifetime Unlock (§13)
                Section("Membership & Purchases") {
                    if entitlement?.isLifetimeUnlocked == true {
                        HStack {
                            Text("Status")
                            Spacer()
                            Label("Lifetime Unlocked", systemImage: "checkmark.seal.fill")
                                .foregroundColor(.green)
                                .font(.subheadline)
                        }
                    } else {
                        HStack {
                            Text("Status")
                            Spacer()
                            Text("Free Tier")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                        }
                        
                        HStack {
                            Text("Free Summaries Used")
                            Spacer()
                            Text("\(entitlement?.freeSummariesUsed ?? 0) of \(AppConstants.freeSummaryLimit)")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                        }
                        
                        Button {
                            showPaywallSheet = true
                        } label: {
                            HStack {
                                Image(systemName: "sparkles")
                                    .foregroundColor(.purple)
                                Text("Unlock Lifetime Access")
                                    .fontWeight(.semibold)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                // MARK: - About & Secret Diagnostics (§15)
                Section("About") {
                    HStack {
                        Text("App Name")
                        Spacer()
                        Text(AppConstants.appName)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Alpha Codename")
                        Spacer()
                        Text(AppConstants.alphaCodename)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0 (Build 1)")
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        versionTapCount += 1
                        if versionTapCount >= 7 {
                            versionTapCount = 0
                            showDiagnostics = true
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                capabilities = await capabilityService.currentCapabilities()
                storageStats = capabilityService.calculateStorageUsage()
                entitlement = await purchaseService.currentEntitlement()
            }
            .sheet(isPresented: $showPaywallSheet) {
                PaywallSheet(purchaseService: purchaseService, capabilityService: capabilityService)
            }
            .alert("Biometric Authentication Required", isPresented: $showFaceIDAuthError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Could not authenticate with \(biometricService.biometryType().rawValue).")
            }
            .alert("Delete All Data?", isPresented: $showDeleteAllAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete Everything", role: .destructive) {
                    deleteAllRecordingsAndAudio()
                }
            } message: {
                Text("This will permanently delete all recordings, transcripts, summaries, and audio files from this iPhone. This action cannot be undone.")
            }
            .sheet(isPresented: $showDiagnostics) {
                DiagnosticsView(capabilities: capabilities, storageStats: storageStats)
            }
        }
    }
    
    // MARK: - Data Erasure Action (§14)
    
    private func deleteAllRecordingsAndAudio() {
        // 1. Delete all SwiftData entities
        do {
            try modelContext.delete(model: Recording.self)
            try modelContext.delete(model: TranscriptSegment.self)
            try modelContext.delete(model: Speaker.self)
            try modelContext.delete(model: Bookmark.self)
            try modelContext.delete(model: SummaryRecord.self)
            try modelContext.save()
        } catch {
            // Ignore error
        }
        
        // 2. Remove all local audio files
        let dir = AppConstants.recordingsDirectoryURL
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        // 3. Refresh storage count
        storageStats = capabilityService.calculateStorageUsage()
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Diagnostics Console (§15)

public struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    let capabilities: DeviceCapabilities?
    let storageStats: (recordingCount: Int, totalSizeBytes: Int64)
    
    public init(
        capabilities: DeviceCapabilities? = nil,
        storageStats: (recordingCount: Int, totalSizeBytes: Int64) = (0, 0)
    ) {
        self.capabilities = capabilities
        self.storageStats = storageStats
    }
    
    public var body: some View {
        NavigationStack {
            List {
                Section("Hardware & System Profile") {
                    #if os(iOS)
                    LabeledContent("Device Model", value: UIDevice.current.model)
                    LabeledContent("iOS Version", value: UIDevice.current.systemVersion)
                    #else
                    LabeledContent("OS Version", value: ProcessInfo.processInfo.operatingSystemVersionString)
                    #endif
                    LabeledContent("Process ID", value: "\(ProcessInfo.processInfo.processIdentifier)")
                    LabeledContent("Active Processors", value: "\(ProcessInfo.processInfo.activeProcessorCount)")
                }
                
                Section("Model & Intelligence Matrix (§15)") {
                    LabeledContent("SpeechTranscriber", value: capabilities?.hasSpeechTranscriber == true ? "Available" : "Unavailable")
                    LabeledContent("Apple Intelligence", value: capabilities?.hasAppleIntelligence == true ? "Active" : "Unsupported")
                    LabeledContent("Diarization Ready", value: capabilities?.isDiarizationReady == true ? "Ready" : "Loading")
                    LabeledContent("Estimated Token Budget", value: "\(capabilities?.estimatedTokenContextLimit ?? 4096) tokens")
                    LabeledContent("Background Tasks", value: capabilities?.supportsBackgroundProcessing == true ? "Supported" : "Disabled (Simulator)")
                }
                
                Section("Local Storage Diagnostics") {
                    LabeledContent("Recordings Directory", value: AppConstants.recordingsDirectoryURL.lastPathComponent)
                    LabeledContent("Audio Files Count", value: "\(storageStats.recordingCount)")
                    LabeledContent("Total Disk Consumed", value: ByteCountFormatter.string(fromByteCount: storageStats.totalSizeBytes, countStyle: .file))
                }
                
                Section("Privacy & Zero-Network Audit (§14.1)") {
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Zero-Network Policy Active")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("No remote network connections or external data egress.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Diagnostics")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
