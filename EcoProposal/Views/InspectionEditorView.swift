import SwiftUI
import SwiftData

/// Editor for a Service Report — Jobsite Condition Assessment. Sections mirror
/// the two-page paper form so techs can fill it out top to bottom on site.
struct InspectionEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var report: InspectionReport
    @State private var showingPDFPreview = false
    @State private var signingRole: InspectionSignatureRole?

    var body: some View {
        List {
            jobInformationSection
            presentOnSiteSection
            reasonForVisitSection
            checklistSections
            testingSection
            findingsSection
            InspectionPhotosSection(report: report)
            acknowledgementSection
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(report.reportNumber)
        .iosInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    saveIfNeeded()
                    showingPDFPreview = true
                } label: {
                    Label("Preview PDF", systemImage: "doc.richtext")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .navigationDestination(isPresented: $showingPDFPreview) {
            InspectionPDFPreviewView(report: report)
        }
        .sheet(item: $signingRole) { role in
            InspectionSignatureSheet(report: report, role: role)
        }
        .onDisappear { saveIfNeeded() }
    }

    // MARK: - 1. Job information

    private var jobInformationSection: some View {
        Section("1. Job information") {
            DatePicker("Date", selection: $report.visitDate, displayedComponents: .date)
            HStack {
                TextField("Arrived", text: $report.arrivedTime)
                TextField("Departed", text: $report.departedTime)
            }
            HStack {
                TextField("Job #", text: $report.jobNumber)
                TextField("Service call #", text: $report.serviceCallNumber)
            }
            TextField("Homeowner", text: $report.homeowner)
            TextField("Builder", text: $report.builder)
            TextField("Address", text: $report.street)
            HStack {
                TextField("City", text: $report.city)
                TextField("State", text: $report.state)
                    .iosUppercaseAutocapitalization()
                    .frame(maxWidth: 80)
                TextField("Zip", text: $report.zip)
                    .iosKeyboardType(.numberPad)
                    .frame(maxWidth: 100)
            }
            TextField("GMX warranty #", text: $report.gmxWarrantyNumber)
            Picker("Warranty term", selection: $report.warrantyTerm) {
                ForEach(GMXWarrantyTerm.allCases) { term in
                    Text(term.displayName).tag(term)
                }
            }
            HStack {
                TextField("Warranty start", text: $report.warrantyStart)
                TextField("End", text: $report.warrantyEnd)
            }
            Toggle("Ultra Shield", isOn: $report.sysUltraShield)
            Toggle("Thermal Drain", isOn: $report.sysThermalDrain)
            Toggle("Dimple Board", isOn: $report.sysDimpleBoard)
            TextField("Other system applied", text: $report.systemOther)
        }
    }

    // MARK: - 2. Present on site

    private var presentOnSiteSection: some View {
        Section("2. Present on site") {
            TextField("Eco-Seal tech", text: $report.techName)
            TextField("Second tech", text: $report.secondTech)
            TextField("Homeowner", text: $report.presentHomeowner)
            TextField("Builder / super", text: $report.presentBuilderSuper)
            TextField("Other", text: $report.presentOther)
            TextField("Company / role", text: $report.presentOtherRole)
        }
    }

    // MARK: - 3. Reason for visit

    private var reasonForVisitSection: some View {
        Section("3. Reason for visit") {
            TextField("Reported by", text: $report.reportedBy)
            TextField("Date first noticed", text: $report.dateFirstNoticed)
            Picker("Recurring?", selection: $report.recurring) {
                ForEach(RecurringAnswer.allCases) { answer in
                    Text(answer.displayName).tag(answer)
                }
            }
            .pickerStyle(.segmented)
            TextField(
                "Issue described / location on the wall",
                text: $report.issueDescription,
                axis: .vertical
            )
            .lineLimit(3...8)
        }
    }

    // MARK: - 4. Jobsite conditions checklist

    @ViewBuilder
    private var checklistSections: some View {
        ForEach(InspectionChecklist.groups) { group in
            Section {
                ForEach(group.itemIndices, id: \.self) { index in
                    checklistRow(index: index)
                }
                groupExtras(for: group)
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("4\(group.id). \(group.title)")
                    Text(group.caption)
                        .font(.caption2)
                        .textCase(nil)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func checklistRow(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(index + 1). \(InspectionChecklist.items[index])")
                .font(.subheadline)
            Picker("Status", selection: Binding(
                get: { report.status(at: index) },
                set: { report.setStatus($0, at: index) }
            )) {
                ForEach(InspectionItemStatus.allCases) { status in
                    Text(status.displayName).tag(status)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func groupExtras(for group: InspectionChecklistGroup) -> some View {
        switch group.id {
        case "A":
            TextField("Notes", text: $report.notesA, axis: .vertical).lineLimit(1...4)
        case "B":
            TextField("Notes", text: $report.notesB, axis: .vertical).lineLimit(1...4)
        case "C":
            Picker("Wall type", selection: $report.wallType) {
                ForEach(WallType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            TextField("Wall notes", text: $report.wallTypeNotes)
        case "D":
            TextField("Drape type", text: $report.drapeType)
            TextField("Notes", text: $report.notesD, axis: .vertical).lineLimit(1...4)
        default:
            EmptyView()
        }
    }

    // MARK: - 5. Testing

    private var testingSection: some View {
        Section("5. Testing") {
            HStack {
                TextField("Flood test start", text: $report.floodTestStart)
                TextField("End", text: $report.floodTestEnd)
            }
            TextField("Flood test result", text: $report.floodTestResult)
            TextField("Humidistat — initial time / reading", text: $report.humidistatInitial)
            TextField("Humidistat — final time / reading", text: $report.humidistatFinal)
        }
    }

    // MARK: - 6. Findings & warranty determination

    private var findingsSection: some View {
        Section {
            Picker("Determination", selection: $report.determination) {
                ForEach(WarrantyDetermination.allCases) { det in
                    Text(det.displayName).tag(det)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            if report.determination == .excluded {
                TextField("Limitation number(s) relied on", text: $report.limitationNumbers)
            }
            Toggle("Photos taken", isOn: $report.photosTaken)
            if report.photosTaken {
                Toggle("Attached separately", isOn: $report.photosAttachedSeparately)
                    .padding(.leading, 16)
            }
            TextField("Findings", text: $report.findings, axis: .vertical)
                .lineLimit(3...8)
            TextField("Action taken / recommended", text: $report.actionTaken, axis: .vertical)
                .lineLimit(3...8)
        } header: {
            Text("6. Findings & warranty determination")
        } footer: {
            Text("If this is a GMX claim: GMX must be notified within 30 days of discovery of the leakage. Coverage cap is the lower of $3.00/sq ft of treated wall or $10,000 project total.")
        }
    }

    // MARK: - 7. Acknowledgement

    private var acknowledgementSection: some View {
        Section {
            signatureRow(
                role: .technician,
                name: report.techName,
                signatureData: report.techSignatureData,
                signedAt: report.techSignedAt
            )
            signatureRow(
                role: .homeowner,
                name: report.presentHomeowner.isEmpty ? report.homeowner : report.presentHomeowner,
                signatureData: report.homeownerSignatureData,
                signedAt: report.homeownerSignedAt
            )
        } header: {
            Text("7. Acknowledgement")
        } footer: {
            Text("Signature acknowledges conditions observed, not liability.")
        }
    }

    private func signatureRow(
        role: InspectionSignatureRole,
        name: String,
        signatureData: Data?,
        signedAt: Date?
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(role.rowTitle)
                if let signedAt {
                    Text("\(name.isEmpty ? "Signed" : name) • \(signedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if signatureData != nil {
                SignaturePreview(signatureData: signatureData)
                    .frame(width: 120, height: 36)
            }
            Button(signatureData == nil ? "Sign" : "Re-sign") {
                signingRole = role
            }
            .buttonStyle(.bordered)
        }
    }

    private func saveIfNeeded() {
        report.updatedAt = Date()
        try? modelContext.save()
    }
}

// MARK: - Signature capture

enum InspectionSignatureRole: String, Identifiable {
    case technician
    case homeowner

    var id: String { rawValue }

    var rowTitle: String {
        switch self {
        case .technician: return "Eco-Seal technician"
        case .homeowner:  return "Homeowner / builder present"
        }
    }

    var heading: String {
        switch self {
        case .technician: return "Sign as Eco-Seal technician"
        case .homeowner:  return "Homeowner / builder acknowledgement"
        }
    }

    var explanation: String {
        switch self {
        case .technician:
            return "I performed this jobsite condition assessment and the conditions recorded are accurate as observed."
        case .homeowner:
            return "Signature acknowledges conditions observed, not liability."
        }
    }
}

/// Lightweight signature sheet for the inspection report acknowledgement block.
struct InspectionSignatureSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var report: InspectionReport
    let role: InspectionSignatureRole

    @State private var draftSignature: Data?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 32)
                .padding(.vertical, 20)
                .background(Color.white)
            }
            .background(Color(white: 0.94))
            .navigationTitle(role.rowTitle)
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
                        .disabled(draftSignature == nil)
                }
            }
        }
        .onAppear {
            switch role {
            case .technician: draftSignature = report.techSignatureData
            case .homeowner:  draftSignature = report.homeownerSignatureData
            }
        }
    }

    private func save() {
        switch role {
        case .technician:
            report.techSignatureData = draftSignature
            report.techSignedAt = Date()
        case .homeowner:
            report.homeownerSignatureData = draftSignature
            report.homeownerSignedAt = Date()
        }
        report.updatedAt = Date()
        try? modelContext.save()
        dismiss()
    }
}
