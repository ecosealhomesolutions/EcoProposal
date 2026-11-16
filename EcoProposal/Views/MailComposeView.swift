import SwiftUI

#if canImport(MessageUI) && os(iOS)
import MessageUI

/// SwiftUI wrapper around `MFMailComposeViewController` — pre-fills the recipient,
/// subject, and body, and attaches the PDF so billing sees it on their side.
struct MailComposeView: UIViewControllerRepresentable {
    let recipients: [String]
    let subject: String
    let body: String
    /// PDF (or any file) to attach. mimeType defaults to `application/pdf`.
    let attachment: URL?
    let mimeType: String
    let onDismiss: (Result<MFMailComposeResult, Error>) -> Void

    init(
        recipients: [String],
        subject: String,
        body: String,
        attachment: URL? = nil,
        mimeType: String = "application/pdf",
        onDismiss: @escaping (Result<MFMailComposeResult, Error>) -> Void = { _ in }
    ) {
        self.recipients = recipients
        self.subject = subject
        self.body = body
        self.attachment = attachment
        self.mimeType = mimeType
        self.onDismiss = onDismiss
    }

    static var canSendMail: Bool { MFMailComposeViewController.canSendMail() }

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients(recipients)
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)

        if let attachment,
           let data = try? Data(contentsOf: attachment) {
            vc.addAttachmentData(data, mimeType: mimeType, fileName: attachment.lastPathComponent)
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onDismiss: (Result<MFMailComposeResult, Error>) -> Void

        init(onDismiss: @escaping (Result<MFMailComposeResult, Error>) -> Void) {
            self.onDismiss = onDismiss
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            controller.dismiss(animated: true) { [self] in
                if let error {
                    onDismiss(.failure(error))
                } else {
                    onDismiss(.success(result))
                }
            }
        }
    }
}
#else
/// Non-iOS placeholder so cross-platform builds still compile.
struct MailComposeView: View {
    let recipients: [String]
    let subject: String
    let body: String
    let attachment: URL?
    let mimeType: String
    var onDismiss: (Result<Int, Error>) -> Void = { _ in }

    static var canSendMail: Bool { false }

    var body: some View {
        Text("Mail compose isn't available on this platform.")
            .padding()
    }
}
#endif
