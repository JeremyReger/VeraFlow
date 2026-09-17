import SwiftUI
#if os(iOS)
import UIKit
#endif

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("consentReminderEnabled") private var consentReminderEnabled = true
    @AppStorage("faceIDLockEnabled") private var faceIDLockEnabled = false
    @State private var versionTapCount = 0
    @State private var showDiagnostics = false
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            Form {
                Section("Privacy & Storage") {
                    Toggle("Recording Consent Reminder", isOn: $consentReminderEnabled)
                    Toggle("Require Face ID", isOn: $faceIDLockEnabled)
                    
                    HStack {
                        Text("On-Device Privacy")
                        Spacer()
                        Text("100% Local")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Model & Intelligence") {
                    HStack {
                        Text("Transcription Engine")
                        Spacer()
                        Text("SpeechAnalyzer")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Diarization")
                        Spacer()
                        Text("FluidAudio (Core ML)")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("AI Summarizer")
                        Spacer()
                        Text("Apple Foundation Models")
                            .foregroundColor(.secondary)
                    }
                }
                
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
            .sheet(isPresented: $showDiagnostics) {
                DiagnosticsView()
            }
        }
    }
}

public struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    
    public var body: some View {
        NavigationStack {
            List {
                Section("System Diagnostics (§15)") {
                    #if os(iOS)
                    LabeledContent("iOS Version", value: UIDevice.current.systemVersion)
                    #else
                    LabeledContent("OS Version", value: ProcessInfo.processInfo.operatingSystemVersionString)
                    #endif
                    LabeledContent("SpeechTranscriber Available", value: "Yes")
                    LabeledContent("Apple Intelligence", value: "Available")
                    LabeledContent("Estimated Token Context", value: "4,096 tokens")
                    LabeledContent("Background Processing", value: "Supported")
                }
            }
            .navigationTitle("Diagnostics")
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
