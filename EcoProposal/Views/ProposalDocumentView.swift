import SwiftUI

/// The printable proposal page. Sized for US Letter (612 x 792 pt).
/// Rendered to PDF by `ProposalPDFRenderer`; also usable as an on-screen preview.
struct ProposalDocumentView: View {
    let snapshot: ProposalSnapshot
    let company: CompanyInfo
    /// The slice of line items shown on THIS page — long tables are split across
    /// pages by the renderer so the signature block is never pushed off the page.
    var pageItems: [LineItemSnapshot]
    /// Progressively reduced (10 → 8pt) as the item count grows.
    var lineItemFontSize: CGFloat
    /// First page carries the parties / lead source / contract scope blocks.
    var isFirstPage: Bool
    /// Closing page carries totals, terms, and the signature block, kept together.
    var isClosingPage: Bool
    /// Shown under the table when the item list continues on the next page.
    var continuationNote: String?

    /// Single-page layout (simple proposals): everything on one page.
    init(snapshot: ProposalSnapshot, company: CompanyInfo) {
        self.init(
            snapshot: snapshot,
            company: company,
            pageItems: snapshot.showLineItemsOnPDF ? snapshot.lineItems : [],
            lineItemFontSize: 10,
            isFirstPage: true,
            isClosingPage: true,
            continuationNote: nil
        )
    }

    init(
        snapshot: ProposalSnapshot,
        company: CompanyInfo,
        pageItems: [LineItemSnapshot],
        lineItemFontSize: CGFloat,
        isFirstPage: Bool,
        isClosingPage: Bool,
        continuationNote: String?
    ) {
        self.snapshot = snapshot
        self.company = company
        self.pageItems = pageItems
        self.lineItemFontSize = lineItemFontSize
        self.isFirstPage = isFirstPage
        self.isClosingPage = isClosingPage
        self.continuationNote = continuationNote
    }

    static let pageSize = CGSize(width: 612, height: 792)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            if isFirstPage {
                partiesBlock
                if hasLeadSource {
                    leadSourceBlock
                }
                if hasContractScope {
                    contractScopeBlock
                }
            }
            if !pageItems.isEmpty {
                lineItemsTable
            }
            if let continuationNote {
                Text(continuationNote)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            if isClosingPage {
                // Totals block ALWAYS renders — the contract needs to show the total,
                // tax, down payment, and balance regardless of per-line pricing.
                totalsBlock
                // Notes render on their own dedicated page (NotesPageView) so long
                // notes never get clipped by a full line-item table.
                if !snapshot.scopeOfWork.isEmpty {
                    Text("See Notes page for project notes.")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
                if !snapshot.terms.isEmpty {
                    sectionBlock(title: "Terms & Conditions", body: snapshot.terms)
                }
                Spacer(minLength: 8)
                signatureBlock
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(36)
        .frame(width: Self.pageSize.width, height: Self.pageSize.height, alignment: .topLeading)
        .background(Color.white)
        .foregroundStyle(.black)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            BrandLogo(height: 58)
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("CONTRACT AGREEMENT")
                    .font(.system(size: 18, weight: .heavy))
                    .tracking(2)
                    .foregroundStyle(Color.ecoNavy)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(company.street)
                    Text(company.cityStateZip)
                    Text("Call: \(company.phone)")
                    Text(company.website)
                }
                .font(.system(size: 9.5))
                .foregroundStyle(Color.ecoNavy.opacity(0.7))
                .padding(.top, 2)
                HStack(spacing: 6) {
                    Text(snapshot.proposalNumber)
                        .font(.system(size: 10, weight: .semibold))
                    Text("•").foregroundStyle(.secondary)
                    Text(snapshot.date, style: .date)
                        .font(.system(size: 10))
                }
                .padding(.top, 2)
            }
        }
    }

    private var partiesBlock: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 3) {
                Text("PREPARED FOR")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(snapshot.customerName.isEmpty ? "—" : snapshot.customerName)
                    .font(.system(size: 12, weight: .semibold))
                if !snapshot.customerCompany.isEmpty {
                    Text(snapshot.customerCompany).font(.system(size: 11))
                }
                if !snapshot.customerAddress.isEmpty {
                    Text(snapshot.customerAddress).font(.system(size: 10))
                }
                if !snapshot.customerEmail.isEmpty {
                    Text(snapshot.customerEmail).font(.system(size: 10))
                }
                if !snapshot.customerPhone.isEmpty {
                    Text(snapshot.customerPhone).font(.system(size: 10))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text("JOB SITE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(snapshot.jobTitle.isEmpty ? "—" : snapshot.jobTitle)
                    .font(.system(size: 12, weight: .semibold))
                if !snapshot.jobSiteAddress.isEmpty {
                    Text(snapshot.jobSiteAddress).font(.system(size: 10))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Lead source

    private var hasLeadSource: Bool {
        !snapshot.inspector.isEmpty || !snapshot.referral.isEmpty
            || (snapshot.permitRequired && snapshot.showPermitOnPDF)
    }

    private var leadSourceBlock: some View {
        HStack(alignment: .top, spacing: 20) {
            if !snapshot.inspector.isEmpty {
                labeledField(label: "Sales Rep", value: snapshot.inspector)
            }
            if !snapshot.referral.isEmpty {
                labeledField(label: "Referral", value: snapshot.referral)
            }
            if snapshot.showPermitOnPDF {
                labeledField(label: "Permit", value: snapshot.permitRequired ? "Yes" : "No")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func labeledField(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value).font(.system(size: 11))
        }
    }

    // MARK: Contract scope checklist

    private var hasContractScope: Bool {
        !exteriorScopeItems.isEmpty || !interiorScopeItems.isEmpty || !serviceScopeItems.isEmpty
    }

    private var exteriorScopeItems: [ScopeLine] {
        var out: [ScopeLine] = []
        if !snapshot.extLinealFeet.isEmpty {
            out.append(ScopeLine(text: "\(snapshot.extLinealFeet) lineal ft of foundation to be dug up", checked: true))
        }
        if snapshot.extWallsWaterproof {
            var s = "Walls treated with waterproofing membrane and insulation/drainage board"
            var flags: [String] = []
            if snapshot.extWallsR5 { flags.append("R5") }
            if snapshot.extWallsR10 { flags.append("R10") }
            if !flags.isEmpty { s += " (\(flags.joined(separator: ", ")))" }
            out.append(ScopeLine(text: s, checked: true))
        }
        if snapshot.extDownspoutDrains { out.append(ScopeLine(text: "Downspout drains replaced in areas of excavation", checked: true)) }
        if snapshot.extBelowGradeDrainage { out.append(ScopeLine(text: "All below-grade drainage scheduled 35 PVC", checked: true)) }
        if snapshot.extACRemoval { out.append(ScopeLine(text: "AC removal and reinstallation", checked: true)) }
        if snapshot.extGravelBackfill {
            var s = "Gravel backfill to aid in drainage"
            if !snapshot.extGravelDepth.isEmpty { s += " (Depth: \(snapshot.extGravelDepth))" }
            out.append(ScopeLine(text: s, checked: true))
        }
        if snapshot.extRoughGrade { out.append(ScopeLine(text: "Rough grade at completion (final grade after settling — not included)", checked: true)) }
        return out
    }

    private var interiorScopeItems: [ScopeLine] {
        var out: [ScopeLine] = []
        if snapshot.intWaterPressureRelief {
            var s = "Interior water-pressure relief system"
            var flags: [String] = []
            if snapshot.intFullVinyl { flags.append("full vinyl") }
            if snapshot.intVinylKicker { flags.append("vinyl kicker") }
            if !flags.isEmpty { s += " (\(flags.joined(separator: ", ")))" }
            out.append(ScopeLine(text: s, checked: true))
        }
        if snapshot.intSumpPump {
            var s = "Sump pump and sump crock install (electrical outlet not included)"
            var flags: [String] = []
            if snapshot.intSumpOutside { flags.append("outside") }
            if snapshot.intSumpInside { flags.append("inside") }
            if !flags.isEmpty { s += " — installed \(flags.joined(separator: " / "))" }
            out.append(ScopeLine(text: s, checked: true))
        }
        if snapshot.intCarbonFiber { out.append(ScopeLine(text: "Carbon Fiber reinforcement", checked: true)) }
        if snapshot.intPowerBrace { out.append(ScopeLine(text: "Power brace steel I-Beam", checked: true)) }
        if snapshot.intHelicalPiers { out.append(ScopeLine(text: "Helical piers", checked: true)) }
        return out
    }

    private var serviceScopeItems: [ScopeLine] {
        var out: [ScopeLine] = []
        if snapshot.svcSumpPump { out.append(ScopeLine(text: "Sump pump repair / replacement", checked: true)) }
        if snapshot.svcBatteryBackup { out.append(ScopeLine(text: "Battery backup pump", checked: true)) }
        if snapshot.svcAnnualMaintenance { out.append(ScopeLine(text: "Annual maintenance inspection", checked: true)) }
        if snapshot.svcDrainCleaning { out.append(ScopeLine(text: "Drain line cleaning / flush", checked: true)) }
        if snapshot.svcCrackRepair { out.append(ScopeLine(text: "Foundation crack repair", checked: true)) }
        if snapshot.svcDehumidifier { out.append(ScopeLine(text: "Dehumidifier install / service", checked: true)) }
        if snapshot.svcWarrantyVisit { out.append(ScopeLine(text: "Warranty service visit", checked: true)) }
        if !snapshot.svcOtherWork.isEmpty { out.append(ScopeLine(text: snapshot.svcOtherWork, checked: true)) }
        return out
    }

    private var contractScopeBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WORK TO BE PERFORMED")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.ecoGreen)

            // Divisions are mutually exclusive: a Service proposal shows a single
            // Service column; Remodel shows the Exterior/Interior pair.
            HStack(alignment: .top, spacing: 24) {
                if !serviceScopeItems.isEmpty {
                    scopeColumn(title: "Service", lines: serviceScopeItems)
                } else {
                    scopeColumn(title: "Exterior", lines: exteriorScopeItems)
                    scopeColumn(title: "Interior", lines: interiorScopeItems)
                }
            }
            .padding(.horizontal, 4)
        }
        .overlay(
            Rectangle().stroke(Color(white: 0.85), lineWidth: 0.5)
        )
    }

    private func scopeColumn(title: String, lines: [ScopeLine]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.ecoGreen)
            if lines.isEmpty {
                Text("—").font(.system(size: 10)).foregroundStyle(.secondary)
            } else {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: line.checked ? "checkmark.square.fill" : "square")
                            .font(.system(size: 10))
                            .foregroundStyle(line.checked ? Color.ecoGreen : .secondary)
                        Text(line.text)
                            .font(.system(size: 10))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Line items

    private var lineItemsTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("Description")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Qty").frame(width: 90, alignment: .trailing)
                if snapshot.showPricingOnPDF {
                    Text("Unit Price").frame(width: 80, alignment: .trailing)
                    Text("Total").frame(width: 90, alignment: .trailing)
                }
            }
            .font(.system(size: lineItemFontSize, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.ecoGreen)

            ForEach(Array(pageItems.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 0) {
                    Text(item.description.isEmpty ? "—" : item.description)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(formatQtyWithUnit(item.quantity, unit: item.unit))
                        .frame(width: 90, alignment: .trailing)
                    if snapshot.showPricingOnPDF {
                        Text(item.unitPrice, format: .currency(code: "USD")).frame(width: 80, alignment: .trailing)
                        Text(item.total, format: .currency(code: "USD")).frame(width: 90, alignment: .trailing)
                    }
                }
                .font(.system(size: lineItemFontSize))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(index.isMultiple(of: 2) ? Color(white: 0.97) : Color.white)
            }
        }
        .overlay(
            Rectangle().stroke(Color(white: 0.85), lineWidth: 0.5)
        )
    }

    private func formatQtyWithUnit(_ qty: Double, unit: String) -> String {
        let base = formatQty(qty)
        return unit.isEmpty ? base : "\(base) \(unit)"
    }

    // MARK: Totals

    private var totalsBlock: some View {
        HStack(alignment: .top, spacing: 16) {
            if snapshot.warranty != .none {
                VStack(alignment: .leading, spacing: 4) {
                    Text("WARRANTY")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(snapshot.warranty.displayName)
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.ecoGreen, lineWidth: 1)
                )
            }
            Spacer()
            VStack(spacing: 4) {
                if snapshot.showLineItemsOnPDF && !snapshot.lineItems.isEmpty {
                    totalRow("Subtotal", snapshot.subtotal, weight: .regular)
                    totalRow("Tax (\(percentString(snapshot.taxRate)))", snapshot.taxAmount, weight: .regular)
                }
                totalRow("Contract Total", snapshot.total, weight: .bold, color: Color.ecoGreen)
                if snapshot.downPayment > 0 {
                    totalRow("Down Payment (20%)", snapshot.downPayment, weight: .regular)
                    Divider().frame(width: 220)
                    totalRow("Unpaid Balance", snapshot.unpaidBalance, weight: .bold)
                    Text("(Due Upon Completion)")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .frame(width: 220, alignment: .trailing)
                }
                Text("Payment via credit card will incur a 3.1% upcharge.")
                    .font(.system(size: 7))
                    .foregroundStyle(.secondary)
                    .frame(width: 220, alignment: .trailing)
            }
        }
    }

    private func totalRow(_ label: String, _ amount: Double, weight: Font.Weight, color: Color = .black) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: weight))
            Spacer()
            Text(amount, format: .currency(code: "USD"))
                .font(.system(size: 11, weight: weight).monospacedDigit())
        }
        .foregroundStyle(color)
        .frame(width: 220)
    }

    private func sectionBlock(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            Text(body).font(.system(size: 10))
        }
    }

    private var signatureBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("I have reviewed the contents and drawings of this agreement with the estimator. I hereby authorize Eco-Seal to do the work specified. I accept the terms and conditions of this agreement.")
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
            Divider()
            HStack(alignment: .bottom, spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    ZStack(alignment: .bottom) {
                        // Rasterized customer signature sits above the baseline.
                        SignaturePreview(signatureData: snapshot.customerSignatureData)
                            .frame(height: 44)
                        Rectangle().fill(Color.black).frame(height: 0.6).frame(maxWidth: .infinity)
                    }
                    HStack(spacing: 6) {
                        Text("Customer approval").font(.system(size: 8)).foregroundStyle(.secondary)
                        if let signedAt = snapshot.customerSignedAt {
                            Text("·").font(.system(size: 8)).foregroundStyle(.secondary)
                            Text(signedAt, format: .dateTime.month().day().year())
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    ZStack(alignment: .bottom) {
                        SignaturePreview(signatureData: snapshot.salesSignatureData)
                            .frame(height: 44)
                        Rectangle().fill(Color.black).frame(height: 0.6).frame(maxWidth: .infinity)
                    }
                    HStack(spacing: 6) {
                        Text("Eco-Seal authorized signature").font(.system(size: 8)).foregroundStyle(.secondary)
                        if let signedBy = snapshot.salesSignedBy, !signedBy.isEmpty {
                            Text("·").font(.system(size: 8)).foregroundStyle(.secondary)
                            Text(signedBy).font(.system(size: 8)).foregroundStyle(.secondary)
                        }
                        if let signedAt = snapshot.salesSignedAt {
                            Text("·").font(.system(size: 8)).foregroundStyle(.secondary)
                            Text(signedAt, format: .dateTime.month().day().year())
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func formatQty(_ qty: Double) -> String {
        if qty == qty.rounded() {
            return String(Int(qty))
        }
        return String(format: "%.2f", qty)
    }

    private func percentString(_ rate: Double) -> String {
        let pct = rate * 100
        if pct == pct.rounded() {
            return "\(Int(pct))%"
        }
        return String(format: "%.2f%%", pct)
    }
}

private struct ScopeLine {
    var text: String
    var checked: Bool
}

// MARK: - Snapshot types

/// Value-type snapshot decoupled from SwiftData so the renderer can safely rebuild
/// the view outside the model context.
struct ProposalSnapshot {
    var proposalNumber: String
    var date: Date
    var taxRate: Double
    var scopeOfWork: String
    var scopeOfWorkRTF: Data?
    var terms: String
    var customerName: String
    var customerCompany: String
    var customerAddress: String
    var customerEmail: String
    var customerPhone: String
    var jobTitle: String
    var jobSiteAddress: String
    var lineItems: [LineItemSnapshot]
    var subtotal: Double
    var taxAmount: Double
    var total: Double
    var sketchData: Data?
    var sketchAnnotations: [SketchAnnotation]
    var sketchSegments: [SketchSegment]
    var sketchCracks: [SketchCrack]
    var photos: [PhotoSnapshot]
    /// Attached literature PDFs, in display order, merged onto the end of the proposal PDF.
    var documentPDFs: [Data]
    var showLineItemsOnPDF: Bool
    var showPricingOnPDF: Bool
    var showPermitOnPDF: Bool
    var customerSignatureData: Data?
    var customerSignedAt: Date?
    var salesSignatureData: Data?
    var salesSignedAt: Date?
    var salesSignedBy: String?

    // Lead source
    var inspector: String
    var referral: String
    var permitRequired: Bool

    // Exterior scope
    var extLinealFeet: String
    var extWallsWaterproof: Bool
    var extWallsR5: Bool
    var extWallsR10: Bool
    var extDownspoutDrains: Bool
    var extBelowGradeDrainage: Bool
    var extACRemoval: Bool
    var extGravelBackfill: Bool
    var extGravelDepth: String
    var extRoughGrade: Bool

    // Interior scope
    var intWaterPressureRelief: Bool
    var intFullVinyl: Bool
    var intVinylKicker: Bool
    var intSumpPump: Bool
    var intSumpOutside: Bool
    var intSumpInside: Bool
    var intCarbonFiber: Bool
    var intPowerBrace: Bool
    var intHelicalPiers: Bool

    // Service scope
    var svcSumpPump: Bool
    var svcBatteryBackup: Bool
    var svcAnnualMaintenance: Bool
    var svcDrainCleaning: Bool
    var svcCrackRepair: Bool
    var svcDehumidifier: Bool
    var svcWarrantyVisit: Bool
    var svcOtherWork: String

    // Payment
    var downPayment: Double
    var unpaidBalance: Double
    var warranty: WarrantyOption

    @MainActor
    init(from proposal: Proposal) {
        self.proposalNumber = proposal.proposalNumber
        self.date = proposal.date
        self.taxRate = proposal.taxRate
        self.scopeOfWork = proposal.scopeOfWork
        self.scopeOfWorkRTF = proposal.scopeOfWorkRTF
        self.terms = proposal.terms

        let customer = proposal.job?.customer
        self.customerName = customer?.name ?? ""
        self.customerCompany = customer?.companyName ?? ""
        self.customerAddress = customer?.formattedAddress ?? ""
        self.customerEmail = customer?.email ?? ""
        self.customerPhone = customer?.phone ?? ""

        self.jobTitle = proposal.job?.title ?? ""
        self.jobSiteAddress = proposal.job?.formattedSiteAddress ?? ""

        self.lineItems = proposal.sortedLineItems.map(LineItemSnapshot.init)
        self.subtotal = proposal.subtotal
        self.taxAmount = proposal.taxAmount
        self.total = proposal.total
        self.sketchData = proposal.sketchData
        self.sketchAnnotations = SketchAnnotationsCodec.decode(proposal.sketchAnnotationsData)
        self.sketchSegments = SketchGeometryCodec.decodeSegments(proposal.sketchSegmentsData)
        self.sketchCracks = SketchGeometryCodec.decodeCracks(proposal.sketchCracksData)
        self.photos = proposal.photos
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(PhotoSnapshot.init)
        self.documentPDFs = proposal.documents
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(\.pdfData)
        self.showLineItemsOnPDF = proposal.showLineItemsOnPDF
        self.showPricingOnPDF = proposal.showPricingOnPDF
        self.showPermitOnPDF = proposal.showPermitOnPDF
        self.customerSignatureData = proposal.customerSignatureData
        self.customerSignedAt = proposal.customerSignedAt
        self.salesSignatureData = proposal.salesSignatureData
        self.salesSignedAt = proposal.salesSignedAt
        self.salesSignedBy = proposal.salesSignedBy

        self.inspector = proposal.inspector
        self.referral = proposal.referral
        self.permitRequired = proposal.permitRequired

        self.extLinealFeet = proposal.extLinealFeet
        self.extWallsWaterproof = proposal.extWallsWaterproof
        self.extWallsR5 = proposal.extWallsR5
        self.extWallsR10 = proposal.extWallsR10
        self.extDownspoutDrains = proposal.extDownspoutDrains
        self.extBelowGradeDrainage = proposal.extBelowGradeDrainage
        self.extACRemoval = proposal.extACRemoval
        self.extGravelBackfill = proposal.extGravelBackfill
        self.extGravelDepth = proposal.extGravelDepth
        self.extRoughGrade = proposal.extRoughGrade

        self.intWaterPressureRelief = proposal.intWaterPressureRelief
        self.intFullVinyl = proposal.intFullVinyl
        self.intVinylKicker = proposal.intVinylKicker
        self.intSumpPump = proposal.intSumpPump
        self.intSumpOutside = proposal.intSumpOutside
        self.intSumpInside = proposal.intSumpInside
        self.intCarbonFiber = proposal.intCarbonFiber
        self.intPowerBrace = proposal.intPowerBrace
        self.intHelicalPiers = proposal.intHelicalPiers

        self.svcSumpPump = proposal.svcSumpPump
        self.svcBatteryBackup = proposal.svcBatteryBackup
        self.svcAnnualMaintenance = proposal.svcAnnualMaintenance
        self.svcDrainCleaning = proposal.svcDrainCleaning
        self.svcCrackRepair = proposal.svcCrackRepair
        self.svcDehumidifier = proposal.svcDehumidifier
        self.svcWarrantyVisit = proposal.svcWarrantyVisit
        self.svcOtherWork = proposal.svcOtherWork

        self.downPayment = proposal.downPayment
        self.unpaidBalance = proposal.unpaidBalance
        self.warranty = proposal.warranty
    }
}

struct PhotoSnapshot {
    var imageData: Data
    var caption: String
    var annotationData: Data?

    @MainActor
    init(from photo: JobPhoto) {
        self.imageData = photo.imageData
        self.caption = photo.caption
        self.annotationData = photo.annotationData
    }
}

struct LineItemSnapshot {
    var description: String
    var quantity: Double
    var unit: String
    var unitPrice: Double
    var total: Double

    @MainActor
    init(from item: LineItem) {
        self.description = item.descriptionText
        self.quantity = item.quantity
        self.unit = item.unit
        self.unitPrice = item.unitPrice
        self.total = item.lineTotal
    }
}
