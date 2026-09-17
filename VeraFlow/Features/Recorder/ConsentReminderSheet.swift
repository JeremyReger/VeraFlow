import SwiftUI

/// Recording consent confirmation sheet adhering to legal two-party notice requirements (§14.2).
public struct ConsentReminderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("consentReminderEnabled") private var consentReminderEnabled = true
    
    @State private var dontShowAgain = false
    
    public let onConfirm: () -> Void
    public let onCancel: () -> Void
    
    public init(
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void = {}
    ) {
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 96, height: 96)
                    
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                        .font(.system(size: 44))
                        .foregroundColor(.orange)
                }
                
                VStack(spacing: 12) {
                    Text("Recording Consent Notice")
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    
                    Text("In many states and jurisdictions, recording a private conversation requires the explicit consent of all participants present.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                    
                    Text("Please notify everyone in the room that this meeting is being recorded.")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                
                Spacer()
                
                VStack(spacing: 16) {
                    Toggle("Don't show this reminder again", isOn: $dontShowAgain)
                        .font(.subheadline)
                        .padding(.horizontal, 8)
                    
                    Button {
                        if dontShowAgain {
                            consentReminderEnabled = false
                        }
                        dismiss()
                        onConfirm()
                    } label: {
                        Text("I Have Consent — Start Recording")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    
                    Button("Cancel", role: .cancel) {
                        dismiss()
                        onCancel()
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    ConsentReminderSheet(onConfirm: {})
}
