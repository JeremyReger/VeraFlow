import SwiftUI

public struct RecorderView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isRecording: Bool = false
    @State private var elapsed: TimeInterval = 0
    @State private var timer: Timer? = nil
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()
                
                VStack(spacing: 8) {
                    Text(formatTime(elapsed))
                        .font(.system(size: 54, weight: .thin, design: .monospaced))
                    
                    Text(isRecording ? "Recording in progress..." : "Ready to record")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                // Audio level waveform placeholder
                HStack(spacing: 4) {
                    ForEach(0..<20, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(isRecording ? Color.red.opacity(Double(i % 5 + 3) / 10.0) : Color.gray.opacity(0.3))
                            .frame(width: 4, height: isRecording ? CGFloat((i * 7) % 40 + 10) : 8)
                    }
                }
                .frame(height: 50)
                
                Spacer()
                
                HStack(spacing: 40) {
                    Button {
                        if isRecording {
                            stopRecording()
                        } else {
                            startRecording()
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .stroke(Color.red, lineWidth: 4)
                                .frame(width: 76, height: 76)
                            
                            if isRecording {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.red)
                                    .frame(width: 28, height: 28)
                            } else {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 60, height: 60)
                            }
                        }
                    }
                }
                .padding(.bottom, 40)
            }
            .navigationTitle("Record Meeting")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        stopRecording()
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func startRecording() {
        isRecording = true
        elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                elapsed += 1
            }
        }
    }
    
    private func stopRecording() {
        isRecording = false
        timer?.invalidate()
        timer = nil
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

#Preview {
    RecorderView()
}
