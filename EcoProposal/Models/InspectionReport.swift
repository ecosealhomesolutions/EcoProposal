import Foundation
import SwiftData

// MARK: - Answer types

/// Tri-state answer for each jobsite-condition checklist row (plus "unset" so a
/// fresh report starts blank, matching the paper form).
enum InspectionItemStatus: String, CaseIterable, Codable, Identifiable {
    case unset
    case ok
    case issue
    case na

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .unset: return "—"
        case .ok:    return "OK"
        case .issue: return "Issue"
        case .na:    return "N/A"
        }
    }
}

enum GMXWarrantyTerm: String, CaseIterable, Codable, Identifiable {
    case unset
    case fifteenYear
    case thirtyYear

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .unset:       return "—"
        case .fifteenYear: return "15 yr"
        case .thirtyYear:  return "30 yr"
        }
    }
}

enum RecurringAnswer: String, CaseIterable, Codable, Identifiable {
    case unset
    case yes
    case no

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .unset: return "—"
        case .yes:   return "Yes"
        case .no:    return "No"
        }
    }
}

enum WallType: String, CaseIterable, Codable, Identifiable {
    case unset
    case poured
    case block
    case icf
    case preCast
    case monolithic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .unset:      return "—"
        case .poured:     return "Poured"
        case .block:      return "Block"
        case .icf:        return "ICF"
        case .preCast:    return "Pre-cast"
        case .monolithic: return "Monolithic"
        }
    }
}

enum WarrantyDetermination: String, CaseIterable, Codable, Identifiable {
    case unset
    case withinSystem
    case excluded
    case undetermined

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .unset:        return "Not determined yet"
        case .withinSystem: return "Within the applied system — GMX claim to be filed"
        case .excluded:     return "Excluded by a GMX warranty limitation — number(s) below"
        case .undetermined: return "Undetermined — further investigation required"
        }
    }
}

// MARK: - Checklist definition

/// The fixed 20-item jobsite-conditions checklist from the paper Service Report,
/// grouped A–D. Item indices (0-based) key into `InspectionReport.checklistRaw`
/// so the editor and the PDF always agree on numbering and wording.
struct InspectionChecklistGroup: Identifiable {
    let id: String          // "A"…"D"
    let title: String
    let caption: String     // GMX limitation reference printed next to the title
    let itemIndices: Range<Int>
}

enum InspectionChecklist {
    static let items: [String] = [
        // A. Site, grading & roof water (1–5)
        "Grade slopes away from foundation — minimum 5% (6\" fall in 10 ft)",
        "Grade line is BELOW the top of the applied waterproofing",
        "Gutters clear and sized; downspouts discharge 8 ft or more from wall",
        "No sprinkler or irrigation wetting an untreated wall",
        "No deck, porch, walk or planter trapping water at the foundation",
        // B. Foundation drainage (6–9)
        "Footer drain present at the base of the foundation",
        "Gravity discharge to daylight — open, not buried or crushed",
        "Sump pump operating, powered, discharge connected and secure",
        "Battery backup pump present",
        // C. Wall & system condition (10–15)
        "No cracks or defects greater than 1/16\" in wall, footing or foundation",
        "No pipe, cable or duct cut through the wall AFTER application",
        "No damage to the applied system from renovation or addition",
        "Wall-to-floor joint sound — construction type noted below",
        "ICF only: pre-formed block used at the brick ledge",
        "No expansion or contraction devices in the wall design",
        // D. Interior conditions (16–20)
        "No condensation on foundation walls or interior finish",
        "Dehumidifier present and running",
        "Interior window seals intact",
        "Interior drape present — type noted below",
        "New construction — concrete still curing, humidity expected",
    ]

    static let groups: [InspectionChecklistGroup] = [
        InspectionChecklistGroup(
            id: "A", title: "Site, Grading & Roof Water",
            caption: "GMX limitation 3.ii · Tips 1–3", itemIndices: 0..<5
        ),
        InspectionChecklistGroup(
            id: "B", title: "Foundation Drainage",
            caption: "GMX limitations 3.i and 9 · Tip 5", itemIndices: 5..<9
        ),
        InspectionChecklistGroup(
            id: "C", title: "Wall & System Condition",
            caption: "GMX limitations 1, 2, 5, 7, 8, 10, 11", itemIndices: 9..<15
        ),
        InspectionChecklistGroup(
            id: "D", title: "Interior Conditions",
            caption: "GMX limitation 4 · Tip 6", itemIndices: 15..<20
        ),
    ]
}

// MARK: - Model

/// A Service Report — Jobsite Condition Assessment for the GMX waterproofing
/// system, mirroring the two-page paper form field for field.
@Model
final class InspectionReport {
    var id: UUID = UUID()
    /// Display number, e.g. "SR-2026-0001".
    var reportNumber: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // 1. Job information
    var visitDate: Date = Date()
    var arrivedTime: String = ""
    var departedTime: String = ""
    var jobNumber: String = ""
    var serviceCallNumber: String = ""
    var homeowner: String = ""
    var builder: String = ""
    var street: String = ""
    var city: String = ""
    var state: String = ""
    var zip: String = ""
    var gmxWarrantyNumber: String = ""
    var warrantyTermRaw: String = GMXWarrantyTerm.unset.rawValue
    var warrantyStart: String = ""
    var warrantyEnd: String = ""
    var sysUltraShield: Bool = false
    var sysThermalDrain: Bool = false
    var sysDimpleBoard: Bool = false
    var systemOther: String = ""

    // 2. Present on site
    var techName: String = ""
    var secondTech: String = ""
    var presentHomeowner: String = ""
    var presentBuilderSuper: String = ""
    var presentOther: String = ""
    var presentOtherRole: String = ""

    // 3. Reason for visit
    var reportedBy: String = ""
    var dateFirstNoticed: String = ""
    var recurringRaw: String = RecurringAnswer.unset.rawValue
    var issueDescription: String = ""

    // 4. Jobsite conditions checklist — one raw InspectionItemStatus per item,
    // indexed to match InspectionChecklist.items.
    var checklistRaw: [String] = Array(repeating: InspectionItemStatus.unset.rawValue, count: 20)
    var notesA: String = ""
    var notesB: String = ""
    var wallTypeRaw: String = WallType.unset.rawValue
    var wallTypeNotes: String = ""
    var drapeType: String = ""
    var notesD: String = ""

    // 5. Testing
    var floodTestStart: String = ""
    var floodTestEnd: String = ""
    var floodTestResult: String = ""
    var humidistatInitial: String = ""
    var humidistatFinal: String = ""

    // 6. Findings & warranty determination
    var determinationRaw: String = WarrantyDetermination.unset.rawValue
    var limitationNumbers: String = ""
    var photosTaken: Bool = false
    var photosAttachedSeparately: Bool = false
    var findings: String = ""
    var actionTaken: String = ""

    /// Site photos documenting the visit, appended to the PDF one per page.
    @Relationship(deleteRule: .cascade, inverse: \JobPhoto.inspection)
    var photos: [JobPhoto] = []

    // 7. Acknowledgement — PKDrawing bytes, nil until signed.
    var techSignatureData: Data?
    var techSignedAt: Date?
    var homeownerSignatureData: Data?
    var homeownerSignedAt: Date?

    init(reportNumber: String = "", visitDate: Date = Date()) {
        self.reportNumber = reportNumber
        self.visitDate = visitDate
    }

    // MARK: Typed accessors

    var warrantyTerm: GMXWarrantyTerm {
        get { GMXWarrantyTerm(rawValue: warrantyTermRaw) ?? .unset }
        set { warrantyTermRaw = newValue.rawValue }
    }

    var recurring: RecurringAnswer {
        get { RecurringAnswer(rawValue: recurringRaw) ?? .unset }
        set { recurringRaw = newValue.rawValue }
    }

    var wallType: WallType {
        get { WallType(rawValue: wallTypeRaw) ?? .unset }
        set { wallTypeRaw = newValue.rawValue }
    }

    var determination: WarrantyDetermination {
        get { WarrantyDetermination(rawValue: determinationRaw) ?? .unset }
        set { determinationRaw = newValue.rawValue }
    }

    /// Status for a checklist row, guarding against out-of-range after any
    /// future checklist growth.
    func status(at index: Int) -> InspectionItemStatus {
        guard checklistRaw.indices.contains(index) else { return .unset }
        return InspectionItemStatus(rawValue: checklistRaw[index]) ?? .unset
    }

    func setStatus(_ status: InspectionItemStatus, at index: Int) {
        while checklistRaw.count <= index {
            checklistRaw.append(InspectionItemStatus.unset.rawValue)
        }
        checklistRaw[index] = status.rawValue
    }

    /// Increments the persistent report counter and returns the next display
    /// number, e.g. "SR-2026-0001". Mirrors CompanyInfo.nextProposalNumber.
    static func nextReportNumber(on date: Date = Date(), defaults: UserDefaults = .standard) -> String {
        let key = "company.inspectionSeq"
        let next = defaults.integer(forKey: key) + 1
        defaults.set(next, forKey: key)
        let year = Calendar.current.component(.year, from: date)
        return String(format: "SR-%04d-%04d", year, next)
    }
}
