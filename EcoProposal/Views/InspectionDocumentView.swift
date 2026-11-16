import SwiftUI

/// The printable Service Report — Jobsite Condition Assessment, styled to match
/// the paper template: navy title band, green section bars, and the three-column
/// OK / ISSUE / N/A checklist. Two fixed US Letter pages.
struct InspectionDocumentView: View {
    let snapshot: InspectionSnapshot
    let company: CompanyInfo
    /// 0 = page 1 (sections 1–4B), 1 = page 2 (4C–7).
    let pageIndex: Int

    static let pageSize = CGSize(width: 612, height: 792)

    private let statusColumnWidth: CGFloat = 38

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if pageIndex == 0 {
                pageOneHeader
                sectionBar("1.  JOB INFORMATION")
                jobInformationBlock
                sectionBar("2.  PRESENT ON SITE")
                presentOnSiteBlock
                sectionBar("3.  REASON FOR VISIT")
                reasonForVisitBlock
                sectionBar("4.  JOBSITE CONDITIONS AGAINST GMX WARRANTY LIMITATIONS")
                statusColumnHeaders
                checklistGroupBlock(InspectionChecklist.groups[0])
                notesRow("Notes", snapshot.notesA)
                checklistGroupBlock(InspectionChecklist.groups[1])
                notesRow("Notes", snapshot.notesB)
            } else {
                pageTwoHeader
                statusColumnHeaders
                checklistGroupBlock(InspectionChecklist.groups[2])
                wallTypeRow
                checklistGroupBlock(InspectionChecklist.groups[3])
                drapeRow
                sectionBar("5.  TESTING")
                testingBlock
                sectionBar("6.  FINDINGS & WARRANTY DETERMINATION")
                findingsBlock
                sectionBar("7.  ACKNOWLEDGEMENT")
                acknowledgementBlock
                gmxClaimNotice
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(36)
        .frame(width: Self.pageSize.width, height: Self.pageSize.height, alignment: .topLeading)
        .background(Color.white)
        .foregroundStyle(.black)
    }

    // MARK: - Headers

    private var pageOneHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("SERVICE REPORT")
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundStyle(.white)
                Text("Jobsite Condition Assessment — GMX Waterproofing System")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.ecoGreen)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(company.name.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                Text("\(company.street), \(company.cityStateZip)")
                Text("\(company.phone) · \(company.website)")
            }
            .font(.system(size: 8))
            .foregroundStyle(Color.ecoGreen)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.ecoNavy)
    }

    private var pageTwoHeader: some View {
        HStack {
            Text("JOBSITE CONDITIONS, continued")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(.white)
            Spacer()
            Text("Job # \(snapshot.jobNumber.isEmpty ? "____________" : snapshot.jobNumber)")
                .font(.system(size: 9))
                .foregroundStyle(Color.ecoGreen)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.ecoNavy)
    }

    private func sectionBar(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .heavy))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.ecoGreen)
    }

    // MARK: - 1. Job information

    private var jobInformationBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                field("Date", snapshot.visitDate.formatted(date: .numeric, time: .omitted))
                field("Arrived", snapshot.arrivedTime)
                field("Departed", snapshot.departedTime)
                field("Job #", snapshot.jobNumber)
                field("Service call #", snapshot.serviceCallNumber)
            }
            HStack(spacing: 12) {
                field("Homeowner", snapshot.homeowner)
                field("Builder", snapshot.builder)
            }
            HStack(spacing: 12) {
                field("Address", snapshot.street)
                field("City", snapshot.city)
                field("State", snapshot.state, width: 50)
                field("Zip", snapshot.zip, width: 70)
            }
            HStack(spacing: 12) {
                field("GMX warranty #", snapshot.gmxWarrantyNumber)
                checkbox("15 yr", snapshot.warrantyTerm == .fifteenYear)
                checkbox("30 yr", snapshot.warrantyTerm == .thirtyYear)
                field("Warranty start", snapshot.warrantyStart)
                field("End", snapshot.warrantyEnd)
            }
            HStack(spacing: 12) {
                Text("System applied")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                checkbox("Ultra Shield", snapshot.sysUltraShield)
                checkbox("Thermal Drain", snapshot.sysThermalDrain)
                checkbox("Dimple Board", snapshot.sysDimpleBoard)
                field("Other", snapshot.systemOther)
            }
        }
    }

    // MARK: - 2. Present on site

    private var presentOnSiteBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                field("Eco-Seal tech", snapshot.techName)
                field("Second tech", snapshot.secondTech)
            }
            HStack(spacing: 12) {
                field("Homeowner", snapshot.presentHomeowner)
                field("Builder / super", snapshot.presentBuilderSuper)
            }
            HStack(spacing: 12) {
                field("Other", snapshot.presentOther)
                field("Company / role", snapshot.presentOtherRole)
            }
        }
    }

    // MARK: - 3. Reason for visit

    private var reasonForVisitBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                field("Reported by", snapshot.reportedBy)
                field("Date first noticed", snapshot.dateFirstNoticed)
                checkbox("Yes", snapshot.recurring == .yes)
                checkbox("No", snapshot.recurring == .no)
                Text("Recurring?")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("ISSUE DESCRIBED / LOCATION ON THE WALL")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(snapshot.issueDescription.isEmpty ? " " : snapshot.issueDescription)
                    .font(.system(size: 9))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 24, alignment: .topLeading)
                    .padding(4)
                    .background(Color(white: 0.96))
            }
        }
    }

    // MARK: - 4. Checklist

    private var statusColumnHeaders: some View {
        HStack(spacing: 0) {
            Spacer()
            ForEach(["OK", "ISSUE", "N/A"], id: \.self) { title in
                Text(title)
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: statusColumnWidth)
            }
        }
    }

    private func checklistGroupBlock(_ group: InspectionChecklistGroup) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text("\(group.id).  \(group.title.uppercased())")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(Color.ecoNavy)
                Text(group.caption)
                    .font(.system(size: 8).italic())
                    .foregroundStyle(.secondary)
            }
            ForEach(group.itemIndices, id: \.self) { index in
                HStack(alignment: .top, spacing: 0) {
                    Text("\(index + 1).")
                        .font(.system(size: 9))
                        .frame(width: 20, alignment: .leading)
                    Text(InspectionChecklist.items[index])
                        .font(.system(size: 9))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    statusCells(snapshot.status(at: index))
                }
            }
        }
    }

    private func statusCells(_ status: InspectionItemStatus) -> some View {
        HStack(spacing: 0) {
            statusCell(marked: status == .ok, color: Color.ecoGreen)
            statusCell(marked: status == .issue, color: .red)
            statusCell(marked: status == .na, color: .gray)
        }
    }

    private func statusCell(marked: Bool, color: Color) -> some View {
        Image(systemName: marked ? "checkmark.square.fill" : "square")
            .font(.system(size: 9))
            .foregroundStyle(marked ? color : Color(white: 0.75))
            .frame(width: statusColumnWidth)
    }

    private func notesRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? " " : value)
                .font(.system(size: 9))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color(white: 0.96))
        }
    }

    private var wallTypeRow: some View {
        HStack(spacing: 12) {
            Text("Wall type")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
            ForEach(WallType.allCases.filter { $0 != .unset }) { type in
                checkbox(type.displayName, snapshot.wallType == type)
            }
            field("", snapshot.wallTypeNotes)
        }
    }

    private var drapeRow: some View {
        HStack(spacing: 12) {
            field("Drape type", snapshot.drapeType)
            field("Notes", snapshot.notesD)
        }
    }

    // MARK: - 5. Testing

    private var testingBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                field("Flood test — start", snapshot.floodTestStart)
                field("End", snapshot.floodTestEnd)
                field("Result", snapshot.floodTestResult)
            }
            HStack(spacing: 12) {
                field("Humidistat — initial time / reading", snapshot.humidistatInitial)
                field("Final time / reading", snapshot.humidistatFinal)
            }
        }
    }

    // MARK: - 6. Findings

    private var findingsBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Based on conditions observed, the reported issue appears to be:")
                .font(.system(size: 9))
            VStack(alignment: .leading, spacing: 3) {
                checkbox("Within the applied system — GMX claim to be filed",
                         snapshot.determination == .withinSystem)
                checkbox("Excluded by a GMX warranty limitation — number(s) below",
                         snapshot.determination == .excluded)
                checkbox("Undetermined — further investigation required",
                         snapshot.determination == .undetermined)
            }
            .padding(.leading, 12)
            HStack(spacing: 12) {
                field("Limitation number(s) relied on", snapshot.limitationNumbers)
                checkbox("Photos taken", snapshot.photosTaken)
                checkbox("Attached separately", snapshot.photosAttachedSeparately)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("FINDINGS")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(snapshot.findings.isEmpty ? " " : snapshot.findings)
                    .font(.system(size: 9))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .topLeading)
                    .padding(4)
                    .background(Color(white: 0.96))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("ACTION TAKEN / RECOMMENDED")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(snapshot.actionTaken.isEmpty ? " " : snapshot.actionTaken)
                    .font(.system(size: 9))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .topLeading)
                    .padding(4)
                    .background(Color(white: 0.96))
            }
        }
    }

    // MARK: - 7. Acknowledgement

    private var acknowledgementBlock: some View {
        HStack(alignment: .bottom, spacing: 24) {
            signatureColumn(
                label: "Eco-Seal technician",
                name: snapshot.techName,
                signatureData: snapshot.techSignatureData,
                signedAt: snapshot.techSignedAt
            )
            signatureColumn(
                label: "Homeowner / builder present",
                name: snapshot.presentHomeowner.isEmpty ? snapshot.homeowner : snapshot.presentHomeowner,
                signatureData: snapshot.homeownerSignatureData,
                signedAt: snapshot.homeownerSignedAt
            )
        }
    }

    private func signatureColumn(
        label: String,
        name: String,
        signatureData: Data?,
        signedAt: Date?
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ZStack(alignment: .bottom) {
                SignaturePreview(signatureData: signatureData)
                    .frame(height: 40)
                Rectangle().fill(Color.black).frame(height: 0.6).frame(maxWidth: .infinity)
            }
            HStack(spacing: 6) {
                Text(label)
                if !name.isEmpty {
                    Text("·")
                    Text(name)
                }
                if let signedAt {
                    Text("·")
                    Text(signedAt, format: .dateTime.month().day().year())
                }
            }
            .font(.system(size: 8))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var gmxClaimNotice: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("IF THIS IS A GMX CLAIM:  GMX must be notified within 30 days of discovery of the leakage.")
                .font(.system(size: 8, weight: .bold))
            Text("GMX, Inc. · PO Box 1557, Indian Trail NC 28079 · 866-228-7743    Coverage cap is the lower of $3.00/sq ft of treated wall or $10,000 project total.")
                .font(.system(size: 7.5))
                .foregroundStyle(.secondary)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ecoGreen.opacity(0.12))
    }

    // MARK: - Shared bits

    private var footer: some View {
        HStack {
            Text("Eco-Seal Home Solutions · Service Report · Jobsite Condition Assessment")
            Spacer()
            Text("Page \(pageIndex + 1) of 2")
        }
        .font(.system(size: 7.5))
        .foregroundStyle(.secondary)
    }

    /// Label + light-gray fill box, matching the template's field styling.
    /// Pass width to pin short fields (State, Zip); omit for flexible.
    private func field(_ label: String, _ value: String, width: CGFloat? = nil) -> some View {
        HStack(spacing: 4) {
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            Text(value.isEmpty ? " " : value)
                .font(.system(size: 9))
                .lineLimit(1)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .frame(maxWidth: width ?? .infinity, alignment: .leading)
                .background(Color(white: 0.96))
        }
        .frame(maxWidth: width == nil ? .infinity : nil)
    }

    private func checkbox(_ label: String, _ checked: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .font(.system(size: 9))
                .foregroundStyle(checked ? Color.ecoGreen : Color(white: 0.6))
            Text(label)
                .font(.system(size: 9))
                .fixedSize()
        }
    }
}

// MARK: - Previews

@MainActor
private func sampleSnapshot() -> InspectionSnapshot {
    let report = InspectionReport(reportNumber: "SR-2026-0001")
    report.arrivedTime = "9:15 AM"
    report.departedTime = "11:40 AM"
    report.jobNumber = "J-4821"
    report.serviceCallNumber = "2"
    report.homeowner = "John & Mary Hershberger"
    report.builder = "Weaver Custom Homes"
    report.street = "4587 TR 606"
    report.city = "Fredericksburg"
    report.state = "OH"
    report.zip = "44627"
    report.gmxWarrantyNumber = "GMX-88213"
    report.warrantyTerm = .thirtyYear
    report.warrantyStart = "06/2023"
    report.warrantyEnd = "06/2053"
    report.sysUltraShield = true
    report.sysDimpleBoard = true
    report.techName = "Phil Hostetler"
    report.presentHomeowner = "John Hershberger"
    report.reportedBy = "Homeowner"
    report.dateFirstNoticed = "Early October"
    report.recurring = .yes
    report.issueDescription = "Damp spot on the north basement wall, lower-left corner near the egress window. Worse after heavy rain."
    for index in 0..<20 { report.setStatus(.ok, at: index) }
    report.setStatus(.issue, at: 2)
    report.setStatus(.na, at: 13)
    report.notesA = "North downspout discharges 3 ft from wall — extended during visit."
    report.wallType = .poured
    report.drapeType = "6-mil poly"
    report.floodTestStart = "9:40"
    report.floodTestEnd = "10:25"
    report.floodTestResult = "No intrusion observed"
    report.determination = .excluded
    report.limitationNumbers = "3.ii"
    report.photosTaken = true
    report.findings = "Moisture tracked to roof water discharging at the foundation; applied system intact where exposed."
    report.actionTaken = "Extended downspout; recommended regrading the north planting bed to restore 5% fall."
    return InspectionSnapshot(from: report)
}

#Preview("Page 1") {
    InspectionDocumentView(snapshot: sampleSnapshot(), company: CompanyInfo.load(), pageIndex: 0)
}

#Preview("Page 2") {
    InspectionDocumentView(snapshot: sampleSnapshot(), company: CompanyInfo.load(), pageIndex: 1)
}

// MARK: - Snapshot

/// Value-type snapshot decoupled from SwiftData so the PDF renderer can safely
/// rebuild the view outside the model context (same pattern as ProposalSnapshot).
struct InspectionSnapshot {
    var reportNumber: String
    var visitDate: Date
    var arrivedTime: String
    var departedTime: String
    var jobNumber: String
    var serviceCallNumber: String
    var homeowner: String
    var builder: String
    var street: String
    var city: String
    var state: String
    var zip: String
    var gmxWarrantyNumber: String
    var warrantyTerm: GMXWarrantyTerm
    var warrantyStart: String
    var warrantyEnd: String
    var sysUltraShield: Bool
    var sysThermalDrain: Bool
    var sysDimpleBoard: Bool
    var systemOther: String

    var techName: String
    var secondTech: String
    var presentHomeowner: String
    var presentBuilderSuper: String
    var presentOther: String
    var presentOtherRole: String

    var reportedBy: String
    var dateFirstNoticed: String
    var recurring: RecurringAnswer
    var issueDescription: String

    var checklistRaw: [String]
    var notesA: String
    var notesB: String
    var wallType: WallType
    var wallTypeNotes: String
    var drapeType: String
    var notesD: String

    var floodTestStart: String
    var floodTestEnd: String
    var floodTestResult: String
    var humidistatInitial: String
    var humidistatFinal: String

    var determination: WarrantyDetermination
    var limitationNumbers: String
    var photosTaken: Bool
    var photosAttachedSeparately: Bool
    var findings: String
    var actionTaken: String

    var techSignatureData: Data?
    var techSignedAt: Date?
    var homeownerSignatureData: Data?
    var homeownerSignedAt: Date?

    /// Site photos in display order, appended to the PDF one per page.
    var photos: [PhotoSnapshot]

    func status(at index: Int) -> InspectionItemStatus {
        guard checklistRaw.indices.contains(index) else { return .unset }
        return InspectionItemStatus(rawValue: checklistRaw[index]) ?? .unset
    }

    @MainActor
    init(from report: InspectionReport) {
        self.reportNumber = report.reportNumber
        self.visitDate = report.visitDate
        self.arrivedTime = report.arrivedTime
        self.departedTime = report.departedTime
        self.jobNumber = report.jobNumber
        self.serviceCallNumber = report.serviceCallNumber
        self.homeowner = report.homeowner
        self.builder = report.builder
        self.street = report.street
        self.city = report.city
        self.state = report.state
        self.zip = report.zip
        self.gmxWarrantyNumber = report.gmxWarrantyNumber
        self.warrantyTerm = report.warrantyTerm
        self.warrantyStart = report.warrantyStart
        self.warrantyEnd = report.warrantyEnd
        self.sysUltraShield = report.sysUltraShield
        self.sysThermalDrain = report.sysThermalDrain
        self.sysDimpleBoard = report.sysDimpleBoard
        self.systemOther = report.systemOther

        self.techName = report.techName
        self.secondTech = report.secondTech
        self.presentHomeowner = report.presentHomeowner
        self.presentBuilderSuper = report.presentBuilderSuper
        self.presentOther = report.presentOther
        self.presentOtherRole = report.presentOtherRole

        self.reportedBy = report.reportedBy
        self.dateFirstNoticed = report.dateFirstNoticed
        self.recurring = report.recurring
        self.issueDescription = report.issueDescription

        self.checklistRaw = report.checklistRaw
        self.notesA = report.notesA
        self.notesB = report.notesB
        self.wallType = report.wallType
        self.wallTypeNotes = report.wallTypeNotes
        self.drapeType = report.drapeType
        self.notesD = report.notesD

        self.floodTestStart = report.floodTestStart
        self.floodTestEnd = report.floodTestEnd
        self.floodTestResult = report.floodTestResult
        self.humidistatInitial = report.humidistatInitial
        self.humidistatFinal = report.humidistatFinal

        self.determination = report.determination
        self.limitationNumbers = report.limitationNumbers
        self.photosTaken = report.photosTaken
        self.photosAttachedSeparately = report.photosAttachedSeparately
        self.findings = report.findings
        self.actionTaken = report.actionTaken

        self.techSignatureData = report.techSignatureData
        self.techSignedAt = report.techSignedAt
        self.homeownerSignatureData = report.homeownerSignatureData
        self.homeownerSignedAt = report.homeownerSignedAt

        self.photos = report.photos
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(PhotoSnapshot.init)
    }
}

// MARK: - Photo pages

/// A single US-Letter page rendering one inspection photo with an optional
/// caption — the inspection counterpart of PhotoPageView.
struct InspectionPhotoPageView: View {
    let photo: PhotoSnapshot
    let pageIndex: Int
    let pageCount: Int
    let reportNumber: String

    static let pageSize = InspectionDocumentView.pageSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                BrandLogo(height: 28)
                Spacer()
                Text("\(reportNumber) • Photo \(pageIndex + 1) of \(pageCount)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if let image = PlatformImage.image(from: photo.imageData) {
                ZStack {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                    PhotoInkOverlay(annotationData: photo.annotationData)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(white: 0.85), lineWidth: 0.5)
                )
            } else {
                Rectangle()
                    .fill(Color(white: 0.95))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(Text("Photo unavailable").foregroundStyle(.secondary))
            }

            if !photo.caption.isEmpty {
                Text(photo.caption)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(36)
        .frame(width: Self.pageSize.width, height: Self.pageSize.height, alignment: .topLeading)
        .background(Color.white)
        .foregroundStyle(.black)
    }
}
