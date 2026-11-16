import SwiftUI
import SwiftData

enum SignatureRole: String, Identifiable {
    case customer
    case sales

    var id: String { rawValue }

    var title: String {
        switch self {
        case .customer: "Customer Signature"
        case .sales:    "Sales Rep Signature"
        }
    }

    var heading: String {
        switch self {
        case .customer: "Sign to accept the proposal"
        case .sales:    "Countersign as Eco-Seal representative"
        }
    }

    var explanation: String {
        switch self {
        case .customer:
            return "I have reviewed the contents and drawings of this agreement with the estimator. I hereby authorize Eco-Seal to do the work specified. I accept the terms and conditions of this agreement."
        case .sales:
            return "I am an authorized representative of Eco-Seal Home Solutions and confirm the details of this contract."
        }
    }
}

/// Full-sheet signature capture. Reused for both customer and sales-rep signing.
struct SignatureCaptureView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var proposal: Proposal
    let role: SignatureRole
    /// Names to offer for "signed by" when role == .sales.
    let salesRoster: [String]

    @State private var draftSignature: Data?
    @State private var signedByName: String

    init(
        proposal: Proposal,
        role: SignatureRole,
        salesRoster: [String] = []
    ) {
        self.proposal = proposal
        self.role = role
        self.salesRoster = salesRoster
        switch role {
        case .customer:
            _draftSignature = State(initialValue: proposal.customerSignatureData)
            _signedByName = State(initialValue: "")
        case .sales:
            _draftSignature = State(initialValue: proposal.salesSignatureData)
            _signedByName = State(initialValue: proposal.salesSignedBy ?? "")
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerBlock
                if role == .sales {
                    salesNamePicker
                }
                signaturePad
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 20)
                    .background(Color.white)
                fineprint
            }
            .background(Color(white: 0.94))
            .navigationTitle(role.title)
            .iosInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .leadingCompat) {
                    Button(role: .destructive) {
                        draftSignature = nil
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .disabled(draftSignature == nil)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save") { save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(draftSignature == nil || (role == .sales && signedByName.isEmpty))
                }
            }
        }
    }

    // MARK: - Sections

    private var headerBlock: some View {
        VStack(spacing: 4) {
            Text(role.heading)
                .font(.headline)
                .foregroundStyle(Color.ecoNavy)
            Text(role.explanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(Color(white: 0.96))
    }

    private var salesNamePicker: some View {
        HStack {
            Text("Signed by")
                .foregroundStyle(.secondary)
            Spacer()
            Picker("Signed by", selection: $signedByName) {
                Text("Choose…").tag("")
                ForEach(salesRoster, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .pickerStyle(.menu)
        }
        .font(.callout)
        .padding(.horizontal, 32)
        .padding(.vertical, 12)
        .background(Color(white: 0.96))
    }

    private var signaturePad: some View {
        ZStack(alignment: .bottom) {
            DrawingCanvas(data: $draftSignature, showsToolPicker: false)
            VStack(spacing: 4) {
                Spacer()
                Rectangle()
                    .fill(Color.black.opacity(0.6))
                    .frame(height: 0.8)
                HStack {
                    Image(systemName: "signature")
                    Text("Sign here")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            }
            .allowsHitTesting(false)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(white: 0.82), lineWidth: 1)
        )
    }

    private var fineprint: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                Text(Date(), style: .date)
                    .fontWeight(.medium)
                Text("Signing date")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // Prominent Clear button — big, red, easy to hit if the customer messes up.
            Button(role: .destructive) {
                draftSignature = nil
            } label: {
                Label("Clear signature", systemImage: "arrow.uturn.backward")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(draftSignature == nil)
        }
        .font(.footnote)
        .padding(.horizontal, 32)
        .padding(.vertical, 14)
    }

    private func save() {
        switch role {
        case .customer:
            proposal.customerSignatureData = draftSignature
            proposal.customerSignedAt = Date()
            if proposal.status == .draft || proposal.status == .sent {
                proposal.status = .accepted
            }
        case .sales:
            proposal.salesSignatureData = draftSignature
            proposal.salesSignedAt = Date()
            proposal.salesSignedBy = signedByName
        }
        proposal.updatedAt = Date()
        try? modelContext.save()
        dismiss()
    }
}
