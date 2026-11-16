import SwiftUI
import SwiftData

struct ProposalEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var proposal: Proposal
    @State private var showingCustomerPicker = false
    @State private var editingCustomer: Customer?
    @State private var showingPDFPreview = false
    @State private var showingSketchEditor = false
    @State private var showingLidarScan = false
    @State private var pendingSketchEditorAfterScan = false
    @State private var showingRemoveSketchConfirmation = false
    @State private var showingCreateVersionConfirmation = false
    var onNavigateToProposal: ((Proposal) -> Void)?
    // Signature capture lives in the Review with Customer flow, not the editor.

    var body: some View {
        List {
            if CloudSync.shared.conflicts.contains(proposal.id) {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Changed on the website too")
                                .font(.headline)
                            Text("Someone edited this proposal on the website while you were editing it here. Choose which version to keep.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    Button("Use the website's version") {
                        Task { await CloudSync.shared.useWebsiteVersion(proposal.id) }
                    }
                    Button("Keep my iPad changes") {
                        Task { await CloudSync.shared.keepIPadVersion(proposal.id) }
                    }
                }
            } else if !CloudSync.shared.canEdit(proposal.id) {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(CloudSync.shared.isLockedInCloud(proposal.id) ? "Signed and locked" : "View only")
                                .font(.headline)
                            Text(CloudSync.shared.isLockedInCloud(proposal.id)
                                 ? "This proposal was signed. To change it, create a new version on the website."
                                 : "This proposal belongs to another rep. Ask them or a manager to add you as a collaborator to edit it.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "icloud.fill")
                            .foregroundStyle(Color.ecoBlue)
                    }
                }
            }
            if proposal.isLocked || proposal.isArchived {
                lockBanner
            }
            Group {
                headerSection
                customerSection
                jobSection
                leadSourceSection
                if proposal.division == .remodel {
                    exteriorScopeSection
                    interiorScopeSection
                }
                if proposal.division == .service {
                    serviceScopeSection
                }
                // New Construction: Takeoff sits above Line Items so measured
                // square footage flows naturally into line-item pricing below.
                if proposal.division == .newConstruction {
                    TakeoffSection(proposal: proposal)
                }
                lineItemsSection
                totalsSection
                scopeAndTermsSection
                if proposal.division == .remodel {
                    sketchSection
                    lidarSection
                }
                PhotosSection(proposal: proposal)
                LiteratureSection(proposal: proposal)
            }
            .disabled(proposal.isLocked || proposal.isArchived || !CloudSync.shared.canEdit(proposal.id))
            reviewSection
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .confirmationDialog(
            "Create a new version?",
            isPresented: $showingCreateVersionConfirmation,
            titleVisibility: .visible
        ) {
            Button("Create New Version") {
                let newVersion = proposal.createNewVersion(in: modelContext)
                onNavigateToProposal?(newVersion)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This archives the signed contract and starts a fresh editable copy with the same customer, line items, photos, and sketch. Signatures are not carried over.")
        }
        .navigationTitle(proposal.proposalNumber.isEmpty ? "Number pending" : proposal.proposalNumber)
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
                .disabled(!canPreview)
            }
        }
        .sheet(isPresented: $showingCustomerPicker) {
            CustomerPickerView { customer in
                assignCustomer(customer)
            }
        }
        .sheet(item: $editingCustomer) { customer in
            EditCustomerSheet(customer: customer)
        }
        .navigationDestination(isPresented: $showingPDFPreview) {
            ProposalPDFPreviewView(proposal: proposal)
        }
        .navigationDestination(for: Blueprint.self) { bp in
            TakeoffEditorView(blueprint: bp)
        }
        .sheet(isPresented: $showingSketchEditor) {
            SketchEditorView(proposal: proposal)
        }
        .lidarScanCover(isPresented: $showingLidarScan) { generated in
            applyGeneratedSketch(generated)
        } onDismiss: {
            // Open the sketch editor only after the scanner cover is fully gone —
            // presenting it during the dismissal wedges SwiftUI's presentation stack.
            if pendingSketchEditorAfterScan {
                pendingSketchEditorAfterScan = false
                showingSketchEditor = true
            }
        }
        .onDisappear { saveIfNeeded() }
    }

    private var canPreview: Bool {
        !proposal.lineItems.isEmpty || hasAnyContractScope || proposal.total > 0
    }

    private var hasAnyContractScope: Bool {
        !proposal.extLinealFeet.isEmpty ||
        proposal.extWallsWaterproof ||
        proposal.extDownspoutDrains ||
        proposal.extBelowGradeDrainage ||
        proposal.extACRemoval ||
        proposal.extGravelBackfill ||
        proposal.extRoughGrade ||
        proposal.intWaterPressureRelief ||
        proposal.intSumpPump ||
        proposal.intCarbonFiber ||
        proposal.intPowerBrace ||
        proposal.intHelicalPiers ||
        proposal.svcSumpPump ||
        proposal.svcBatteryBackup ||
        proposal.svcAnnualMaintenance ||
        proposal.svcDrainCleaning ||
        proposal.svcCrackRepair ||
        proposal.svcDehumidifier ||
        proposal.svcWarrantyVisit ||
        !proposal.svcOtherWork.isEmpty
    }

    // MARK: - Sections

    private var lockBanner: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: proposal.isArchived ? "archivebox.fill" : "lock.fill")
                    .font(.title2)
                    .foregroundStyle(proposal.isArchived ? .secondary : Color.ecoGreen)
                VStack(alignment: .leading, spacing: 3) {
                    Text(proposal.isArchived ? "Archived version" : "Signed & Locked")
                        .font(.headline)
                    if let signedBy = proposal.salesSignedBy, !signedBy.isEmpty,
                       let signedAt = proposal.salesSignedAt {
                        Text("Countersigned by \(signedBy) • \(signedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let customerSignedAt = proposal.customerSignedAt {
                        Text("Customer signed \(customerSignedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let superseded = proposal.supersedesProposalNumber {
                        Text("Supersedes \(superseded)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(proposal.isArchived
                         ? "This is a historical record. To change the current contract, open the newer version from the Proposals sidebar."
                         : "The contract details are frozen. To make changes, create a new version — the current signed contract will be archived.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
            if !proposal.isArchived {
                Button {
                    showingCreateVersionConfirmation = true
                } label: {
                    Label("Create New Version", systemImage: "square.on.square")
                }
            }
        }
    }

    private var headerSection: some View {
        Section {
            LabeledContent("Proposal #", value: proposal.proposalNumber.isEmpty ? "Assigned when synced" : proposal.proposalNumber)
            DatePicker("Date", selection: $proposal.date, displayedComponents: .date)
            Picker("Status", selection: Binding(get: { proposal.status }, set: { proposal.status = $0 })) {
                ForEach(ProposalStatus.allCases) { status in
                    Text(status.displayName).tag(status)
                }
            }
        }
    }

    private var customerSection: some View {
        Section("Customer") {
            if let customer = proposal.job?.customer {
                VStack(alignment: .leading, spacing: 4) {
                    Text(customer.displayName).font(.headline)
                    if let email = customer.email, !email.isEmpty {
                        Text(email).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let phone = customer.phone, !phone.isEmpty {
                        Text(phone).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let addr = customer.formattedAddress {
                        Text(addr).font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button {
                        editingCustomer = customer
                    } label: {
                        Label("Edit customer", systemImage: "pencil")
                    }
                    Spacer()
                    Button("Change customer") { showingCustomerPicker = true }
                }
            } else {
                Button {
                    showingCustomerPicker = true
                } label: {
                    Label("Choose customer", systemImage: "person.crop.circle.badge.plus")
                }
            }
        }
    }

    private var jobSection: some View {
        Section("Job") {
            TextField("Job title", text: Binding(
                get: { proposal.job?.title ?? "" },
                set: { newValue in ensureJob().title = newValue }
            ))
            TextField("Street", text: Binding(
                get: { proposal.job?.siteStreet ?? "" },
                set: { newValue in ensureJob().siteStreet = newValue.isEmpty ? nil : newValue }
            ))
            TextField("City", text: Binding(
                get: { proposal.job?.siteCity ?? "" },
                set: { newValue in ensureJob().siteCity = newValue.isEmpty ? nil : newValue }
            ))
            HStack {
                TextField("State", text: Binding(
                    get: { proposal.job?.siteState ?? "" },
                    set: { newValue in ensureJob().siteState = newValue.isEmpty ? nil : newValue }
                ))
                .iosUppercaseAutocapitalization()
                .frame(maxWidth: 120)
                TextField("ZIP", text: Binding(
                    get: { proposal.job?.siteZip ?? "" },
                    set: { newValue in ensureJob().siteZip = newValue.isEmpty ? nil : newValue }
                ))
                .iosKeyboardType(.numberPad)
            }
        }
    }

    private var leadSourceSection: some View {
        Section("Lead source") {
            Picker("Sales Rep", selection: $proposal.inspector) {
                Text("None").tag("")
                ForEach(salesRepRoster, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            TextField("Referral", text: $proposal.referral)
            Toggle("Permit required", isOn: $proposal.permitRequired)
            Toggle("Show permit on customer PDF", isOn: $proposal.showPermitOnPDF)
            if !proposal.showPermitOnPDF {
                Text("The permit line is hidden from the customer-facing PDF. The permit-required setting is still saved internally.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Reps from EcoProposal Cloud (active sales reps, managers, admins); built-in list until the first sync.
    private var salesRepRoster: [String] {
        CloudSyncState.shared.salesRepNames(fallback: Self.fallbackSalesRepRoster)
    }

    private static let fallbackSalesRepRoster = [
        "Caleb Palmer",
        "Dan Yoder",
        "Michael Arnold",
        "Jason Miller",
        "Tony Nickles",
        "Phil Hostetler",
        "Joe Burkholder",
        "Jon Dreher"
    ]

    private var exteriorScopeSection: some View {
        Section("Exterior work") {
            HStack {
                Text("Lineal ft to dig up")
                Spacer()
                TextField("0", text: $proposal.extLinealFeet)
                    .iosKeyboardType(.decimal)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
            }
            Toggle("Waterproofing membrane + insulation", isOn: $proposal.extWallsWaterproof)
            if proposal.extWallsWaterproof {
                Toggle("R5 board", isOn: $proposal.extWallsR5).padding(.leading, 16)
                Toggle("R10 board", isOn: $proposal.extWallsR10).padding(.leading, 16)
            }
            Toggle("Downspout drains (in areas of excavation)", isOn: $proposal.extDownspoutDrains)
            Toggle("Below-grade drainage schedule 35 PVC", isOn: $proposal.extBelowGradeDrainage)
            Toggle("AC removal + reinstallation", isOn: $proposal.extACRemoval)
            Toggle("Gravel backfill", isOn: $proposal.extGravelBackfill)
            if proposal.extGravelBackfill {
                HStack {
                    Text("Depth").padding(.leading, 16)
                    Spacer()
                    TextField("e.g. 6 in", text: $proposal.extGravelDepth)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 140)
                }
            }
            Toggle("Rough grade at completion", isOn: $proposal.extRoughGrade)
        }
    }

    private var interiorScopeSection: some View {
        Section("Interior work") {
            Toggle("Interior water-pressure relief", isOn: $proposal.intWaterPressureRelief)
            if proposal.intWaterPressureRelief {
                Toggle("Full vinyl", isOn: $proposal.intFullVinyl).padding(.leading, 16)
                Toggle("Vinyl kicker", isOn: $proposal.intVinylKicker).padding(.leading, 16)
            }
            Toggle("Sump pump + sump crock", isOn: $proposal.intSumpPump)
            if proposal.intSumpPump {
                Toggle("Outside", isOn: $proposal.intSumpOutside).padding(.leading, 16)
                Toggle("Inside", isOn: $proposal.intSumpInside).padding(.leading, 16)
            }
            Toggle("Carbon Fiber reinforcement", isOn: $proposal.intCarbonFiber)
            Toggle("Power brace steel I-Beam", isOn: $proposal.intPowerBrace)
            Toggle("Helical piers", isOn: $proposal.intHelicalPiers)
        }
    }

    private var serviceScopeSection: some View {
        Section("Service work") {
            Toggle("Sump pump repair / replacement", isOn: $proposal.svcSumpPump)
            Toggle("Battery backup pump", isOn: $proposal.svcBatteryBackup)
            Toggle("Annual maintenance inspection", isOn: $proposal.svcAnnualMaintenance)
            Toggle("Drain line cleaning / flush", isOn: $proposal.svcDrainCleaning)
            Toggle("Foundation crack repair", isOn: $proposal.svcCrackRepair)
            Toggle("Dehumidifier install / service", isOn: $proposal.svcDehumidifier)
            Toggle("Warranty service visit", isOn: $proposal.svcWarrantyVisit)
            TextField("Other service work", text: $proposal.svcOtherWork, axis: .vertical)
                .lineLimit(1...4)
        }
    }

    private var lineItemsSection: some View {
        Section {
            ForEach(proposal.sortedLineItems) { item in
                LineItemRow(item: item)
            }
            .onDelete(perform: deleteLineItems)

            Button {
                addLineItem()
            } label: {
                Label("Add line item", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("Line items (pricing)")
        }
    }

    private var totalsSection: some View {
        Section("Totals & payment") {
            HStack {
                Text("Subtotal")
                Spacer()
                Text(proposal.subtotal, format: .currency(code: "USD"))
                    .monospacedDigit()
            }
            HStack {
                Text("Tax rate")
                Spacer()
                TextField(
                    "Tax rate",
                    value: Binding(
                        get: { proposal.taxRate * 100 },
                        set: { proposal.taxRate = $0 / 100 }
                    ),
                    format: .number.precision(.fractionLength(0...3))
                )
                .iosKeyboardType(.decimal)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                Text("%")
            }
            HStack {
                Text("Tax")
                Spacer()
                Text(proposal.taxAmount, format: .currency(code: "USD"))
                    .monospacedDigit()
            }
            HStack {
                Text("Contract total").font(.headline)
                Spacer()
                Text(proposal.total, format: .currency(code: "USD"))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Color.ecoGreen)
            }
            HStack {
                Text("Down payment (20%)")
                Spacer()
                Text(proposal.downPayment, format: .currency(code: "USD"))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Unpaid balance")
                Spacer()
                Text(proposal.unpaidBalance, format: .currency(code: "USD"))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Picker("Warranty", selection: Binding(get: { proposal.warranty }, set: { proposal.warranty = $0 })) {
                ForEach(WarrantyOption.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            Toggle("Show line items on PDF", isOn: $proposal.showLineItemsOnPDF)
            Toggle("Show unit price on line items", isOn: $proposal.showPricingOnPDF)
            if !proposal.showPricingOnPDF {
                Text("Line items will show description + quantity only. Contract Total, tax, and down payment are still shown — this only hides the per-item pricing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sketchSection: some View {
        Section("Job sketch") {
            let annotations = SketchAnnotationsCodec.decode(proposal.sketchAnnotationsData)
            let segments = SketchGeometryCodec.decodeSegments(proposal.sketchSegmentsData)
            let cracks = SketchGeometryCodec.decodeCracks(proposal.sketchCracksData)
            if proposal.sketchData != nil || !annotations.isEmpty || !segments.isEmpty || !cracks.isEmpty {
                SketchThumbnail(
                    sketchData: proposal.sketchData,
                    annotations: annotations,
                    segments: segments,
                    cracks: cracks
                )
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                Button {
                    showingSketchEditor = true
                } label: {
                    Label("Edit sketch", systemImage: "pencil.and.outline")
                }
                // Destructive action is intentionally hidden behind a menu +
                // confirmation dialog so an accidental tap can't wipe the sketch.
                Menu {
                    Button("Remove sketch", role: .destructive) {
                        showingRemoveSketchConfirmation = true
                    }
                } label: {
                    Label("More…", systemImage: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
                .confirmationDialog(
                    "Remove this sketch?",
                    isPresented: $showingRemoveSketchConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Remove", role: .destructive) {
                        proposal.sketchData = nil
                        proposal.sketchAnnotationsData = nil
                        proposal.sketchSegmentsData = nil
                        proposal.sketchCracksData = nil
                        proposal.updatedAt = Date()
                        try? modelContext.save()
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("This deletes the drawing and any shape/note annotations on it. You can always draw a new one.")
                }
            } else {
                Button {
                    showingSketchEditor = true
                } label: {
                    Label("Draw job sketch", systemImage: "square.and.pencil")
                }
            }
        }
    }

    /// LiDAR capture lives directly beneath the hand-drawn sketch. A scan measures
    /// the house and drops a to-scale floor plan into the sketch so the rep can mark
    /// it up — the long-term replacement for drawing the layout by hand.
    @ViewBuilder
    private var lidarSection: some View {
        #if os(iOS)
        if LidarSupport.isAvailable {
            Section {
                Button {
                    showingLidarScan = true
                } label: {
                    Label("Scan house with LiDAR", systemImage: "camera.metering.matrix")
                }
                Text("Walk the room to capture measurements. We'll turn the scan into a to-scale floor plan you can draw on in the sketch editor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("LiDAR measurement")
            }
        }
        #endif
    }

    /// Writes a scan-generated floor plan into the proposal's sketch fields and
    /// flags the sketch editor to open once the scanner cover finishes dismissing.
    private func applyGeneratedSketch(_ generated: GeneratedSketch) {
        proposal.sketchData = generated.drawingData
        proposal.sketchAnnotationsData = SketchAnnotationsCodec.encode(generated.annotations)
        proposal.updatedAt = Date()
        try? modelContext.save()
        pendingSketchEditorAfterScan = true
    }

    private var reviewSection: some View {
        Section {
            Button {
                saveIfNeeded()
                showingPDFPreview = true
            } label: {
                HStack {
                    Spacer()
                    Label(reviewCTATitle, systemImage: "arrow.right.circle.fill")
                        .font(.headline)
                    Spacer()
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canPreview)
        } footer: {
            Text(reviewCTAFooter)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var reviewCTATitle: String {
        switch proposal.division {
        case .remodel, .service: return "Review with Customer"
        case .newConstruction:   return "Preview & Send Proposal"
        }
    }

    private var reviewCTAFooter: String {
        switch proposal.division {
        case .remodel, .service:
            return "Opens a preview matching what the customer will see on the PDF. From there they can sign, and you can countersign, share, and save to OneDrive."
        case .newConstruction:
            return "Opens a full preview so you can share the proposal with the customer, save to OneDrive, or email it directly."
        }
    }

    @ViewBuilder
    private var scopeAndTermsSection: some View {
        Section {
            RichTextEditor(
                rtfData: $proposal.scopeOfWorkRTF,
                plainText: $proposal.scopeOfWork,
                placeholder: "Additional notes about the job…"
            )
        } header: {
            Text("Notes")
        } footer: {
            Text("Select text to format it, or use the B / I / U buttons above the keyboard. Long notes flow across multiple PDF pages automatically.")
        }
        Section("Terms & conditions") {
            TextField("Terms", text: $proposal.terms, axis: .vertical)
                .lineLimit(3...10)
        }
    }

    // MARK: - Actions

    private func ensureJob() -> Job {
        if let job = proposal.job { return job }
        let job = Job(title: "")
        modelContext.insert(job)
        proposal.job = job
        return job
    }

    private func assignCustomer(_ customer: Customer) {
        ensureJob().customer = customer
        try? modelContext.save()
    }

    private func addLineItem() {
        let nextSort = (proposal.lineItems.map(\.sortOrder).max() ?? -1) + 1
        let item = LineItem(sortOrder: nextSort, proposal: proposal)
        modelContext.insert(item)
        proposal.lineItems.append(item)
    }

    private func deleteLineItems(offsets: IndexSet) {
        let sorted = proposal.sortedLineItems
        for index in offsets {
            let item = sorted[index]
            modelContext.delete(item)
        }
    }

    private func saveIfNeeded() {
        autoAttachFortressIfNeeded()
        proposal.updatedAt = Date()
        try? modelContext.save()
    }

    /// Proposals bidding Fortress products automatically carry the Fortress
    /// brochure. Runs on save/preview; attaches at most once per proposal so a
    /// rep who removes the brochure from this proposal doesn't get it back.
    private func autoAttachFortressIfNeeded() {
        guard !proposal.fortressAutoAttached else { return }
        let hasFortressItem = proposal.lineItems.contains {
            $0.descriptionText.localizedCaseInsensitiveContains("fortress")
        }
        guard hasFortressItem else { return }

        // Find the Fortress document in the shared library.
        let fortressFilename = BundledLiterature.fortressFilename
        let descriptor = FetchDescriptor<LibraryDocument>(
            predicate: #Predicate { $0.filename == fortressFilename }
        )
        guard let libraryDoc = try? modelContext.fetch(descriptor).first else { return }

        // Already attached manually? Just mark the flag.
        proposal.fortressAutoAttached = true
        guard !proposal.documents.contains(where: { $0.filename == libraryDoc.filename }) else { return }

        let nextSort = (proposal.documents.map(\.sortOrder).max() ?? -1) + 1
        let document = ProposalDocument(
            title: libraryDoc.title,
            filename: libraryDoc.filename,
            pdfData: libraryDoc.pdfData,
            sortOrder: nextSort,
            proposal: proposal
        )
        modelContext.insert(document)
        proposal.documents.append(document)
    }
}
