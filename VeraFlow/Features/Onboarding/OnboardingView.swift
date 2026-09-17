import SwiftUI
import AVFoundation

/// Three-screen onboarding flow establishing value proposition, 100% on-device privacy, and microphone access (§4.1).
public struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    @State private var currentPage = 0
    @State private var micPermissionGranted = false
    @State private var capabilities: DeviceCapabilities? = nil
    
    private let capabilityService: CapabilityServiceProtocol
    
    public init(capabilityService: CapabilityServiceProtocol = CapabilityService()) {
        self.capabilityService = capabilityService
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                welcomeScreen.tag(0)
                privacyScreen.tag(1)
                permissionsScreen.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            
            // Bottom Action Bar
            VStack(spacing: 12) {
                if currentPage < 2 {
                    Button {
                        withAnimation {
                            currentPage += 1
                        }
                    } label: {
                        Text("Continue")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                } else {
                    Button {
                        completeOnboarding()
                    } label: {
                        Text("Get Started")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .task {
            capabilities = await capabilityService.currentCapabilities()
            checkMicrophoneStatus()
        }
    }
    
    // MARK: - Screen 1: Value Proposition (§4.1)
    
    private var welcomeScreen: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.blue.opacity(0.2), .purple.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "waveform.badge.magnifyingglass")
                    .font(.system(size: 54))
                    .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            
            VStack(spacing: 10) {
                Text("Welcome to \(AppConstants.appName)")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text("Private, on-device meeting notes and actionable summaries.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            
            VStack(alignment: .leading, spacing: 20) {
                featureRow(
                    icon: "sparkles",
                    color: .purple,
                    title: "Action-Oriented Templates",
                    subtitle: "Executive overviews, contractor walk-through measurements, and client proposals."
                )
                
                featureRow(
                    icon: "person.2.wave.2.fill",
                    color: .blue,
                    title: "Speaker Diarization",
                    subtitle: "Distinguishes who spoke what with seamless rename and merge controls."
                )
                
                featureRow(
                    icon: "checklist",
                    color: .green,
                    title: "Actionable Follow-ups",
                    subtitle: "Tasks with assigned owners, resolved due dates, and one-tap Apple Reminders sync."
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            
            Spacer()
        }
    }
    
    // MARK: - Screen 2: 100% On-Device Privacy (§4.1, §14.1)
    
    private var privacyScreen: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 54))
                    .foregroundColor(.green)
            }
            
            VStack(spacing: 10) {
                Text("100% On-Device Privacy")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text("Zero data leaves your iPhone. Period.")
                    .font(.headline)
                    .foregroundColor(.green)
            }
            
            VStack(alignment: .leading, spacing: 20) {
                featureRow(
                    icon: "network.slash",
                    color: .teal,
                    title: "Zero Cloud Telemetry",
                    subtitle: "No tracking SDKs, no external analytics, and zero cloud LLM egress."
                )
                
                featureRow(
                    icon: "cpu",
                    color: .indigo,
                    title: "Local Apple Intelligence",
                    subtitle: "Transcription and summarization run completely on Apple Neural Engine."
                )
                
                featureRow(
                    icon: "touchid",
                    color: .orange,
                    title: "Biometric Protection",
                    subtitle: "Secure your audio archives behind Face ID with encrypted storage."
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            
            Spacer()
        }
    }
    
    // MARK: - Screen 3: Permissions & Capabilities (§4.1, §15)
    
    private var permissionsScreen: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "mic.fill.badge.plus")
                    .font(.system(size: 54))
                    .foregroundColor(.blue)
            }
            
            VStack(spacing: 8) {
                Text("Permissions & Capabilities")
                    .font(.title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text("VeraFlow requires microphone access to record meetings on your device.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
            
            // Capability Notice Box (§15)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: capabilities?.hasAppleIntelligence == true ? "checkmark.circle.fill" : "info.circle.fill")
                        .foregroundColor(capabilities?.hasAppleIntelligence == true ? .green : .orange)
                    Text("Device Intelligence Profile")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                Text(capabilities?.honestCapabilityMessage ?? "Transcripts work on this iPhone; AI summaries need an Apple Intelligence–capable iPhone.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(14)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 24)
            
            // Microphone Permission Button
            Button {
                requestMicrophonePermission()
            } label: {
                HStack {
                    Image(systemName: micPermissionGranted ? "checkmark.circle.fill" : "mic.fill")
                    Text(micPermissionGranted ? "Microphone Access Granted" : "Enable Microphone Access")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.bordered)
            .tint(micPermissionGranted ? .green : .blue)
            .disabled(micPermissionGranted)
            .padding(.horizontal, 24)
            
            Spacer()
        }
    }
    
    // MARK: - Helpers
    
    private func featureRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    private func checkMicrophoneStatus() {
        #if os(iOS)
        let status = AVAudioApplication.shared.recordPermission
        micPermissionGranted = (status == .granted)
        #else
        micPermissionGranted = true
        #endif
    }
    
    private func requestMicrophonePermission() {
        #if os(iOS)
        AVAudioApplication.requestRecordPermission { granted in
            Task { @MainActor in
                self.micPermissionGranted = granted
            }
        }
        #else
        micPermissionGranted = true
        #endif
    }
    
    private func completeOnboarding() {
        hasCompletedOnboarding = true
        dismiss()
    }
}

#Preview {
    OnboardingView()
}
