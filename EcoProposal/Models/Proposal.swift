import Foundation
import SwiftData

enum Division: String, CaseIterable, Codable, Identifiable {
    case remodel
    case newConstruction
    case service

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .remodel:         return "Remodel"
        case .newConstruction: return "New Construction"
        case .service:         return "Service"
        }
    }

    var systemImage: String {
        switch self {
        case .remodel:         return "hammer.fill"
        case .newConstruction: return "building.2.fill"
        case .service:         return "wrench.and.screwdriver.fill"
        }
    }
}

enum ProposalStatus: String, CaseIterable, Codable, Identifiable {
    case draft
    case sent
    case accepted
    case declined

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .draft: return "Draft"
        case .sent: return "Sent"
        case .accepted: return "Accepted"
        case .declined: return "Declined"
        }
    }
}

enum WarrantyOption: String, CaseIterable, Codable, Identifiable {
    case none
    case thirtyYear
    case lifetime

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:       return "None"
        case .thirtyYear: return "30 Year"
        case .lifetime:   return "Lifetime"
        }
    }
}

@Model
final class Proposal {
    var id: UUID
    var proposalNumber: String
    var date: Date
    var statusRaw: String
    /// Which line of business this proposal belongs to. Drives which sections
    /// the editor exposes (Remodel = sketch + foundation checklist; New
    /// Construction = takeoff / blueprints).
    var divisionRaw: String = Division.remodel.rawValue
    var taxRate: Double
    var scopeOfWork: String
    /// Rich-text (RTF) version of the notes, carrying bold/italic/underline from
    /// the WYSIWYG editor. `scopeOfWork` is kept in sync as the plain-text mirror
    /// for search/sync; the PDF prefers this when present.
    var scopeOfWorkRTF: Data?
    var terms: String
    var job: Job?
    var remoteRecordID: Int?
    var updatedAt: Date

    /// Raw PKDrawing.dataRepresentation() bytes for the free-drawn ink layer of the job sketch.
    var sketchData: Data?

    /// JSON-encoded `[SketchAnnotation]` for shape stamps + quick-note text placed on the sketch.
    var sketchAnnotationsData: Data?

    /// JSON-encoded `[SketchSegment]` — straight wall segments drawn with the Walls tool.
    var sketchSegmentsData: Data?

    /// JSON-encoded `[SketchCrack]` — foundation cracks drawn with the Crack tool.
    var sketchCracksData: Data?

    /// PKDrawing bytes of the customer's on-site signature. nil until signed.
    var customerSignatureData: Data?

    /// Timestamp when the customer signed the proposal on the iPad.
    var customerSignedAt: Date?

    /// PKDrawing bytes of the sales rep's countersignature. nil until signed.
    var salesSignatureData: Data?

    /// Timestamp when the rep countersigned.
    var salesSignedAt: Date?

    /// Display name of the rep who countersigned (matches inspectorRoster values).
    var salesSignedBy: String?

    // MARK: - Contract fields (mirrors Eco-Seal Home Solutions paper contract)

    // Lead source
    var inspector: String
    var referral: String
    var permitRequired: Bool

    // Exterior scope
    var extLinealFeet: String            // e.g. "45"
    var extWallsWaterproof: Bool
    var extWallsR5: Bool
    var extWallsR10: Bool
    var extDownspoutDrains: Bool
    var extBelowGradeDrainage: Bool
    var extACRemoval: Bool
    var extGravelBackfill: Bool
    var extGravelDepth: String           // e.g. "6 in"
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

    // Service scope (Service division checklist; inline defaults so existing
    // stores migrate without a schema version bump)
    var svcSumpPump: Bool = false
    var svcBatteryBackup: Bool = false
    var svcAnnualMaintenance: Bool = false
    var svcDrainCleaning: Bool = false
    var svcCrackRepair: Bool = false
    var svcDehumidifier: Bool = false
    var svcWarrantyVisit: Bool = false
    var svcOtherWork: String = ""

    // Payment + warranty (downPayment is computed as 20% of total — no stored value)
    var warrantyRaw: String

    // PDF options
    var showLineItemsOnPDF: Bool = true
    /// When false, hides all pricing from the PDF — line item unit/total columns,
    /// subtotals, taxes, contract total, down payment, and balance. Useful for
    /// sharing scope with builders / subcontractors without revealing markup.
    var showPricingOnPDF: Bool = true

    /// When false, hides the "Permit" field from the customer-facing PDF. The
    /// permit-required flag is still stored for internal use — this only controls
    /// whether it prints.
    var showPermitOnPDF: Bool = true

    /// Set once the Fortress brochure has been auto-attached because a Fortress
    /// line item exists. Prevents re-attaching after a rep deliberately removes it.
    var fortressAutoAttached: Bool = false

    // Versioning / archival
    /// True once this proposal has been superseded by a newer signed version.
    var isArchived: Bool = false
    /// If this proposal was created as a new version of an older one, this
    /// records the original's proposal number for display ("Supersedes P-2026-0001").
    var supersedesProposalNumber: String?

    @Relationship(deleteRule: .cascade, inverse: \LineItem.proposal)
    var lineItems: [LineItem] = []

    @Relationship(deleteRule: .cascade, inverse: \JobPhoto.proposal)
    var photos: [JobPhoto] = []

    @Relationship(deleteRule: .cascade, inverse: \Blueprint.proposal)
    var blueprints: [Blueprint] = []

    @Relationship(deleteRule: .cascade, inverse: \ProposalDocument.proposal)
    var documents: [ProposalDocument] = []

    init(
        id: UUID = UUID(),
        proposalNumber: String = "",
        date: Date = Date(),
        status: ProposalStatus = .draft,
        division: Division = .remodel,
        taxRate: Double = 0,
        scopeOfWork: String = "",
        terms: String = "",
        job: Job? = nil,
        remoteRecordID: Int? = nil,
        updatedAt: Date = Date(),
        inspector: String = "",
        referral: String = "",
        permitRequired: Bool = false,
        extLinealFeet: String = "",
        extWallsWaterproof: Bool = false,
        extWallsR5: Bool = false,
        extWallsR10: Bool = false,
        extDownspoutDrains: Bool = false,
        extBelowGradeDrainage: Bool = false,
        extACRemoval: Bool = false,
        extGravelBackfill: Bool = false,
        extGravelDepth: String = "",
        extRoughGrade: Bool = false,
        intWaterPressureRelief: Bool = false,
        intFullVinyl: Bool = false,
        intVinylKicker: Bool = false,
        intSumpPump: Bool = false,
        intSumpOutside: Bool = false,
        intSumpInside: Bool = false,
        intCarbonFiber: Bool = false,
        intPowerBrace: Bool = false,
        intHelicalPiers: Bool = false,
        warranty: WarrantyOption = .none,
        showLineItemsOnPDF: Bool = true
    ) {
        self.id = id
        self.proposalNumber = proposalNumber
        self.date = date
        self.statusRaw = status.rawValue
        self.divisionRaw = division.rawValue
        self.taxRate = taxRate
        self.scopeOfWork = scopeOfWork
        self.terms = terms
        self.job = job
        self.remoteRecordID = remoteRecordID
        self.updatedAt = updatedAt
        self.inspector = inspector
        self.referral = referral
        self.permitRequired = permitRequired
        self.extLinealFeet = extLinealFeet
        self.extWallsWaterproof = extWallsWaterproof
        self.extWallsR5 = extWallsR5
        self.extWallsR10 = extWallsR10
        self.extDownspoutDrains = extDownspoutDrains
        self.extBelowGradeDrainage = extBelowGradeDrainage
        self.extACRemoval = extACRemoval
        self.extGravelBackfill = extGravelBackfill
        self.extGravelDepth = extGravelDepth
        self.extRoughGrade = extRoughGrade
        self.intWaterPressureRelief = intWaterPressureRelief
        self.intFullVinyl = intFullVinyl
        self.intVinylKicker = intVinylKicker
        self.intSumpPump = intSumpPump
        self.intSumpOutside = intSumpOutside
        self.intSumpInside = intSumpInside
        self.intCarbonFiber = intCarbonFiber
        self.intPowerBrace = intPowerBrace
        self.intHelicalPiers = intHelicalPiers
        self.warrantyRaw = warranty.rawValue
        self.showLineItemsOnPDF = showLineItemsOnPDF
    }

    /// 20% of the contract total, computed on the fly so it auto-adjusts as pricing changes.
    static let downPaymentRate: Double = 0.20
    var downPayment: Double { total * Self.downPaymentRate }

    /// Both parties signed — the contract is executed.
    var isFullySigned: Bool {
        customerSignatureData != nil && salesSignatureData != nil
    }

    /// When true, the editor treats this proposal as read-only. Changes require
    /// creating a new version (via `createNewVersion(in:)`).
    var isLocked: Bool { isFullySigned }

    var status: ProposalStatus {
        get { ProposalStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }

    var division: Division {
        get { Division(rawValue: divisionRaw) ?? .remodel }
        set { divisionRaw = newValue.rawValue }
    }

    var warranty: WarrantyOption {
        get { WarrantyOption(rawValue: warrantyRaw) ?? .none }
        set { warrantyRaw = newValue.rawValue }
    }

    var sortedLineItems: [LineItem] {
        lineItems.sorted { $0.sortOrder < $1.sortOrder }
    }

    var subtotal: Double {
        lineItems.reduce(0) { $0 + $1.lineTotal }
    }

    var taxAmount: Double {
        subtotal * taxRate
    }

    var total: Double {
        subtotal + taxAmount
    }

    /// Balance the customer still owes on completion.
    var unpaidBalance: Double {
        max(0, total - downPayment)
    }

    /// Duplicates this proposal into a fresh, editable draft with the same
    /// customer/job, line items, photos, and sketch — but no signatures. Marks
    /// this proposal as archived so the immutable signed record is preserved.
    /// Returns the new proposal so the caller can select/navigate to it.
    @MainActor
    @discardableResult
    func createNewVersion(in context: ModelContext) -> Proposal {
        let newProposal = Proposal(
            // Signed in to EcoProposal Cloud: the database assigns the number on upload.
            proposalNumber: CloudSync.shared.isActive ? "" : CompanyInfo.nextProposalNumber(),
            date: Date(),
            status: .draft,
            division: division,
            taxRate: taxRate,
            scopeOfWork: scopeOfWork,
            terms: terms,
            job: job,                       // same customer + job
            inspector: inspector,
            referral: referral,
            permitRequired: permitRequired,
            extLinealFeet: extLinealFeet,
            extWallsWaterproof: extWallsWaterproof,
            extWallsR5: extWallsR5,
            extWallsR10: extWallsR10,
            extDownspoutDrains: extDownspoutDrains,
            extBelowGradeDrainage: extBelowGradeDrainage,
            extACRemoval: extACRemoval,
            extGravelBackfill: extGravelBackfill,
            extGravelDepth: extGravelDepth,
            extRoughGrade: extRoughGrade,
            intWaterPressureRelief: intWaterPressureRelief,
            intFullVinyl: intFullVinyl,
            intVinylKicker: intVinylKicker,
            intSumpPump: intSumpPump,
            intSumpOutside: intSumpOutside,
            intSumpInside: intSumpInside,
            intCarbonFiber: intCarbonFiber,
            intPowerBrace: intPowerBrace,
            intHelicalPiers: intHelicalPiers,
            warranty: warranty,
            showLineItemsOnPDF: showLineItemsOnPDF
        )
        newProposal.sketchData = sketchData
        newProposal.sketchAnnotationsData = sketchAnnotationsData
        newProposal.sketchSegmentsData = sketchSegmentsData
        newProposal.sketchCracksData = sketchCracksData
        newProposal.scopeOfWorkRTF = scopeOfWorkRTF
        newProposal.showPricingOnPDF = showPricingOnPDF
        newProposal.showPermitOnPDF = showPermitOnPDF
        newProposal.svcSumpPump = svcSumpPump
        newProposal.svcBatteryBackup = svcBatteryBackup
        newProposal.svcAnnualMaintenance = svcAnnualMaintenance
        newProposal.svcDrainCleaning = svcDrainCleaning
        newProposal.svcCrackRepair = svcCrackRepair
        newProposal.svcDehumidifier = svcDehumidifier
        newProposal.svcWarrantyVisit = svcWarrantyVisit
        newProposal.svcOtherWork = svcOtherWork
        newProposal.supersedesProposalNumber = proposalNumber

        context.insert(newProposal)

        // Duplicate line items so they belong to the new proposal (relationships
        // can't be shared across owners).
        for item in sortedLineItems {
            let copy = LineItem(
                descriptionText: item.descriptionText,
                quantity: item.quantity,
                unitPrice: item.unitPrice,
                sortOrder: item.sortOrder,
                proposal: newProposal
            )
            context.insert(copy)
            newProposal.lineItems.append(copy)
        }

        // Duplicate attached literature so the new version carries the same docs.
        for document in documents.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            let copy = ProposalDocument(
                title: document.title,
                filename: document.filename,
                pdfData: document.pdfData,
                sortOrder: document.sortOrder,
                proposal: newProposal
            )
            context.insert(copy)
            newProposal.documents.append(copy)
        }

        // Duplicate photos + their annotations.
        for photo in photos {
            let copy = JobPhoto(
                imageData: photo.imageData,
                caption: photo.caption,
                sortOrder: photo.sortOrder,
                proposal: newProposal
            )
            copy.annotationData = photo.annotationData
            context.insert(copy)
            newProposal.photos.append(copy)
        }

        // Archive the original so it stays visible in the list but read-only.
        isArchived = true
        updatedAt = Date()

        try? context.save()
        return newProposal
    }
}
