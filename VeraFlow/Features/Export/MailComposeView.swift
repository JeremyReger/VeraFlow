import SwiftUI
@preconcurrency import MessageUI

/// UIViewControllerRepresentable bridging SwiftUI to MFMailComposeViewController (§12).
public struct MailComposeView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    public let subject: String
    public let body: String
    public let isHTML: Bool
    
    public init(subject: String, body: String, isHTML: Bool = false) {
        self.subject = subject
        self.body = body
        self.isHTML = isHTML
    }
    
    public func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: isHTML)
        return vc
    }
    
    public func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    @MainActor
    public final class Coordinator: NSObject, @preconcurrency MFMailComposeViewControllerDelegate {
        let parent: MailComposeView
        
        init(_ parent: MailComposeView) {
            self.parent = parent
        }
        
        public func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            parent.dismiss()
        }
    }
}
