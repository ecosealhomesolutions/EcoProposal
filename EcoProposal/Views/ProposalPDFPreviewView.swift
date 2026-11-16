import SwiftUI

struct ProposalPDFPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let proposal: Proposal
    @State private var pdfURL: URL?
    @State private var errorMessage: String?

    @State private var oneDrive = LiveOneDriveClient()
    @State private var uploadState: UploadState = .idle
    @State private var showingUploadOptions = false

    // Signature capture flow lives here so the customer only sees the preview,
    // never the itemized editor.
    @State private var pendingSignatureRole: SignatureRole?
    @State private var showingSendToBilling = false
    @State private var pendingBillingRequest: BillingMailRequest?
    @State private var pendingCustomerRequest: BillingMailRequest?
    @State private var mailUnavailableMessage: String?

    private let lastFolderKey = "onedrive.lastFolderPath"

    /// Billing contacts the countersigning rep can hand the executed proposal off to.
    private let billingContacts: [BillingContact] = [
        BillingContact(name: "Tori Miller", email: "tori@ecosealsolutions.com"),
        BillingContact(name: "Ellie Miller", email: "ellie@ecosealsolutions.com"),
    ]

    private let salesRepRoster = [
        "Caleb Palmer",
        "Dan Yoder",
        "Michael Arnold",
        "Jason Miller",
        "Tony Nickles",
        "Phil Hostetler",
        "Joe Burkholder",
        "Jon Dreher"
    ]

    enum UploadState: Equatable {
        case idle
        case uploading
        case uploaded(URL, sizeLabel: String)
        case failed(String)
    }

    var body: some View {
        Group {
            if let pdfURL {
                PDFPreviewer(url: pdfURL)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Rendering PDF…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(white: 0.9))
            }
        }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    signatureActionBar
                    uploadStatusBar
                }
            }
            .background(Color(white: 0.9))
            .navigationTitle("Review with Customer")
            .iosInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if let url = pdfURL {
                        HStack(spacing: 8) {
                            oneDriveButton(pdfURL: url)
                            ShareLink(item: url) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                        }
                    } else {
                        ProgressView()
                    }
                }
            }
            .task {
                await generatePDF()
            }
            .alert("Couldn't create PDF", isPresented: .constant(errorMessage != nil), presenting: errorMessage) { _ in
                Button("OK") { errorMessage = nil }
            } message: { message in
                Text(message)
            }
            .sheet(isPresented: $showingUploadOptions) {
                if let url = pdfURL {
                    UploadOptionsSheet(
                        defaultFilename: url.lastPathComponent,
                        defaultFolder: defaultFolder()
                    ) { filename, folder in
                        UserDefaults.standard.set(folder, forKey: lastFolderKey)
                        Task { await uploadToOneDrive(pdfURL: url, filename: filename, folder: folder) }
                    }
                }
            }
            .sheet(item: $pendingSignatureRole, onDismiss: {
                // Regenerate the PDF after signing so the embedded signature updates immediately.
                Task { await generatePDF() }
            }) { role in
                SignatureCaptureView(
                    proposal: proposal,
                    role: role,
                    salesRoster: salesRepRoster
                )
            }
            .sheet(item: $pendingBillingRequest) { request in
                #if os(iOS)
                MailComposeView(
                    recipients: [request.recipient],
                    subject: request.subject,
                    body: request.body,
                    attachment: request.attachment
                )
                .ignoresSafeArea()
                #else
                Text("Mail compose unavailable on this platform.")
                #endif
            }
            .sheet(item: $pendingCustomerRequest) { request in
                #if os(iOS)
                MailComposeView(
                    recipients: [request.recipient],
                    subject: request.subject,
                    body: request.body,
                    attachment: request.attachment
                )
                .ignoresSafeArea()
                #else
                Text("Mail compose unavailable on this platform.")
                #endif
            }
            .alert("Mail not set up",
                   isPresented: .constant(mailUnavailableMessage != nil),
                   presenting: mailUnavailableMessage) { _ in
                Button("OK") { mailUnavailableMessage = nil }
            } message: { message in
                Text(message)
            }
    }

    // MARK: - Signature action bar

    @ViewBuilder
    private var signatureActionBar: some View {
        VStack(spacing: 8) {
            if proposal.division == .newConstruction {
                // New Construction: no signing on this iPad — just send to the customer.
                if let pdfURL, hasCustomerEmail {
                    Button {
                        prepareSendToCustomer(pdfURL: pdfURL)
                    } label: {
                        Label("Send Proposal to Customer", systemImage: "paperplane.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.ecoNavy)
                } else if pdfURL != nil {
                    Text("Add a customer email in the editor to enable direct send. You can still use Share above.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            } else {
                HStack(spacing: 12) {
                    signatureButton(
                        role: .customer,
                        title: "Customer Sign",
                        icon: "signature",
                        isSigned: proposal.customerSignatureData != nil
                    )
                    signatureButton(
                        role: .sales,
                        title: proposal.salesSignedBy.map { "Countersign (\($0))" } ?? "Countersign",
                        icon: "checkmark.seal",
                        isSigned: proposal.salesSignatureData != nil
                    )
                }
                // Only surface Send to Billing once the sales rep has countersigned —
                // that's the moment the paperwork is truly done and ready to hand off.
                if proposal.salesSignatureData != nil {
                    Button {
                        showingSendToBilling = true
                    } label: {
                        Label("Send to Billing", systemImage: "paperplane.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.ecoNavy)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .confirmationDialog(
            "Send to Billing",
            isPresented: $showingSendToBilling,
            titleVisibility: .visible
        ) {
            ForEach(billingContacts) { contact in
                Button(contact.displayLabel) {
                    sendToBilling(contact)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Email the executed proposal PDF to a billing contact.")
        }
    }

    private func signatureButton(
        role: SignatureRole,
        title: String,
        icon: String,
        isSigned: Bool
    ) -> some View {
        Button {
            pendingSignatureRole = role
        } label: {
            HStack {
                Image(systemName: isSigned ? "checkmark.seal.fill" : icon)
                    .foregroundStyle(isSigned ? Color.ecoGreen : Color.ecoNavy)
                Text(isSigned ? "\(title) — signed" : title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.ecoNavy)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSigned ? Color.ecoGreen.opacity(0.12) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSigned ? Color.ecoGreen : Color(white: 0.8), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - OneDrive button + status

    @ViewBuilder
    private func oneDriveButton(pdfURL: URL) -> some View {
        Button {
            showingUploadOptions = true
        } label: {
            switch uploadState {
            case .idle, .failed:
                Label("OneDrive", systemImage: "cloud.fill")
            case .uploading:
                ProgressView()
            case .uploaded:
                Label("Uploaded", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color.ecoGreen)
            }
        }
        .disabled(uploadState == .uploading)
    }

    @ViewBuilder
    private var uploadStatusBar: some View {
        switch uploadState {
        case .idle:
            EmptyView()
        case .uploading:
            HStack {
                ProgressView()
                Text("Uploading to OneDrive…").font(.footnote)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
        case .uploaded(let url, let sizeLabel):
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.ecoGreen)
                Text("Saved to OneDrive (\(sizeLabel))").font(.footnote)
                Spacer()
                Link("Open", destination: url).font(.footnote)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
        case .failed(let message):
            HStack {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message).font(.footnote).lineLimit(2)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
        }
    }

    // MARK: - Actions

    private func defaultFolder() -> String {
        UserDefaults.standard.string(forKey: lastFolderKey) ?? oneDrive.config.folderPath
    }

    @MainActor
    private func generatePDF() async {
        do {
            let url = try ProposalPDFRenderer.renderPDF(for: proposal, company: CompanyInfo.load())
            self.pdfURL = url
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    private var hasCustomerEmail: Bool {
        !(proposal.job?.customer?.email?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
    }

    /// Composes an email to the customer with the proposal PDF attached.
    /// New Construction workflow — no signing on the iPad; the customer receives
    /// the proposal and responds by their own channel.
    private func prepareSendToCustomer(pdfURL: URL) {
        guard let email = proposal.job?.customer?.email?.trimmingCharacters(in: .whitespaces),
              !email.isEmpty else {
            mailUnavailableMessage = "Add a customer email in the editor first."
            return
        }
        let customerName = proposal.job?.customer?.displayName ?? "there"
        let firstName = customerName.split(separator: " ").first.map(String.init) ?? customerName
        let subject = "Your Eco-Seal proposal \(proposal.proposalNumber)"
        let body = """
            Hi \(firstName),

            Attached is the proposal for your project. Please review and let me know if you have any questions.

            Contract Total: \(proposal.total.formatted(.currency(code: "USD")))
            Down Payment (20%): \(proposal.downPayment.formatted(.currency(code: "USD")))
            Balance Due Upon Completion: \(proposal.unpaidBalance.formatted(.currency(code: "USD")))

            Thanks,
            \(proposal.inspector.isEmpty ? "Eco-Seal Home Solutions" : proposal.inspector)
            """

        if MailComposeView.canSendMail {
            pendingCustomerRequest = BillingMailRequest(
                recipient: email,
                subject: subject,
                body: body,
                attachment: pdfURL
            )
        } else {
            mailUnavailableMessage = "Mail isn't set up on this iPad. Opening the share sheet instead."
            shareToBillingViaSystemShareSheet(pdfURL: pdfURL)
        }
    }

    /// Opens an in-app Mail composer with the billing contact pre-filled and the
    /// signed PDF attached. Falls back to the share sheet if Mail isn't set up.
    private func sendToBilling(_ contact: BillingContact) {
        guard let pdfURL else { return }
        let customerName = proposal.job?.customer?.displayName ?? "customer"
        let subject = "Signed Proposal \(proposal.proposalNumber) — \(customerName)"
        let body = """
            Hi \(contact.firstName),

            Attached is the signed proposal \(proposal.proposalNumber) for \(customerName). Please process for billing.

            Contract Total: \(proposal.total.formatted(.currency(code: "USD")))
            Down Payment (20%): \(proposal.downPayment.formatted(.currency(code: "USD")))
            Balance Due Upon Completion: \(proposal.unpaidBalance.formatted(.currency(code: "USD")))

            Thanks,
            \(proposal.salesSignedBy ?? "Eco-Seal")
            """

        if MailComposeView.canSendMail {
            pendingBillingRequest = BillingMailRequest(
                recipient: contact.email,
                subject: subject,
                body: body,
                attachment: pdfURL
            )
        } else {
            // No configured Mail account — fall back to the share sheet.
            mailUnavailableMessage = "Mail isn't set up on this iPad. Opening the share sheet so you can send the PDF from another app."
            shareToBillingViaSystemShareSheet(pdfURL: pdfURL)
        }
    }

    private func shareToBillingViaSystemShareSheet(pdfURL: URL) {
        #if canImport(UIKit)
        let av = UIActivityViewController(activityItems: [pdfURL], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
            var top = root
            while let presented = top.presentedViewController {
                top = presented
            }
            av.popoverPresentationController?.sourceView = top.view
            av.popoverPresentationController?.sourceRect = CGRect(
                x: top.view.bounds.midX, y: top.view.bounds.maxY - 40, width: 1, height: 1
            )
            av.popoverPresentationController?.permittedArrowDirections = []
            top.present(av, animated: true)
        }
        #endif
    }

    private func uploadToOneDrive(pdfURL: URL, filename: String, folder: String) async {
        uploadState = .uploading
        do {
            // Upload a compressed variant (photos downsampled to ~150 DPI, text and
            // drawings stay vector) so proposals with lots of photos fit in email
            // and don't bloat OneDrive. Falls back to the preview PDF on failure.
            var uploadURL = pdfURL
            var sizeLabel = "original size"
            if let compressed = try? await MainActor.run(body: {
                try ProposalPDFRenderer.renderCompressedPDF(for: proposal, company: CompanyInfo.load())
            }) {
                uploadURL = compressed.url
                sizeLabel = ByteCountFormatter.string(
                    fromByteCount: Int64(compressed.bytes), countStyle: .file
                )
            }

            let webURL = try await oneDrive.uploadPDF(
                fileURL: uploadURL,
                filename: filename,
                folder: folder
            )
            uploadState = .uploaded(webURL, sizeLabel: sizeLabel)
        } catch {
            uploadState = .failed(error.localizedDescription)
        }
    }
}

// MARK: - Billing contacts

struct BillingContact: Identifiable, Hashable {
    let name: String
    let email: String

    var id: String { email }
    var firstName: String { name.split(separator: " ").first.map(String.init) ?? name }
    var displayLabel: String { "\(name) — \(email)" }
}

/// Snapshot of the in-flight billing email so `.sheet(item:)` can present the
/// Mail composer with the pre-filled recipient / subject / body / attachment.
struct BillingMailRequest: Identifiable {
    let id = UUID()
    let recipient: String
    let subject: String
    let body: String
    let attachment: URL
}

// MARK: - Upload options sheet

private struct UploadOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let defaultFilename: String
    let defaultFolder: String
    var onConfirm: (_ filename: String, _ folder: String) -> Void

    @State private var filename: String
    @State private var folder: String

    init(
        defaultFilename: String,
        defaultFolder: String,
        onConfirm: @escaping (_ filename: String, _ folder: String) -> Void
    ) {
        self.defaultFilename = defaultFilename
        self.defaultFolder = defaultFolder
        self.onConfirm = onConfirm
        _filename = State(initialValue: defaultFilename)
        _folder = State(initialValue: defaultFolder)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Filename", text: $filename)
                        .iosNoAutocapitalization()
                } header: {
                    Text("File")
                } footer: {
                    Text("Will be saved as \(filename.hasSuffix(".pdf") ? filename : "\(filename).pdf")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    TextField("Folder", text: $folder)
                        .iosNoAutocapitalization()
                } header: {
                    Text("OneDrive folder")
                } footer: {
                    Text("Files land at /\(folder.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/\(filename.hasSuffix(".pdf") ? filename : "\(filename).pdf")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Save to OneDrive")
            .iosInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Upload") {
                        onConfirm(filename, folder)
                        dismiss()
                    }
                    .disabled(
                        filename.trimmingCharacters(in: .whitespaces).isEmpty ||
                        folder.trimmingCharacters(in: .whitespaces).isEmpty
                    )
                }
            }
        }
        .presentationDetents([.medium])
    }
}
