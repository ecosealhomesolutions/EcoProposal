import Foundation
import Observation
import SwiftData
import Supabase

/// Downloads EcoProposal Cloud data into the iPad's local database
/// (Phase 3, session 2: web → iPad, one way).
///
/// - Customers, jobs, proposals and line items keep the same IDs as the cloud.
/// - Records that came from the cloud are tracked in `CloudSyncState` and are
///   read-only on the iPad until two-way sync ships (session 3).
/// - Proposals created on this iPad are never touched.
/// - Runs at launch, when the app returns to the foreground, every 2 minutes
///   while open, and on pull-to-refresh.
@MainActor
@Observable
final class CloudSync {
    static let shared = CloudSync()

    private(set) var isSyncing = false
    private(set) var lastError: String?

    private let client = SupabaseService.client
    private let state = CloudSyncState.shared
    private var context: ModelContext?
    private var autoSyncTask: Task<Void, Never>?

    private init() {}

    // MARK: - Scheduling

    func startAutoSync(context: ModelContext) {
        self.context = context
        guard autoSyncTask == nil else { return }
        autoSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pullNow()
                try? await Task.sleep(for: .seconds(120))
            }
        }
    }

    func stopAutoSync() {
        autoSyncTask?.cancel()
        autoSyncTask = nil
    }

    // MARK: - Pull

    func pullNow() async {
        guard let context, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            let org: [CloudOrganization] = try await fetchAll("organizations", columns: "id, default_tax_rate, default_terms")
            let profiles: [CloudProfileRow] = try await fetchAll("profiles", columns: "id, full_name, role, active")
            let customers: [CloudCustomer] = try await fetchAll("customers", columns: "id, name, company_name, email, phone, street, city, state, zip")
            let jobs: [CloudJob] = try await fetchAll("jobs", columns: "id, customer_id, title, site_street, site_city, site_state, site_zip, notes")
            let proposals: [CloudProposal] = try await fetchAll(
                "proposals",
                columns: "id, job_id, number, proposal_date, division, status, tax_rate, terms, scope_text, scope_checklist, warranty, inspector, referral, permit_required, pdf_options, is_archived, supersedes_id, locked_at"
            )
            let lineItems: [CloudLineItem] = try await fetchAll("line_items", columns: "id, proposal_id, description, quantity, unit, unit_price, sort_order")
            let library: [CloudLibraryDocument] = try await fetchAll("library_documents", columns: "id, title, file_path, auto_attach_rule")

            applyCompanyDefaults(org.first)
            let repNames = profiles
                .filter { $0.active && ["sales_rep", "manager", "admin"].contains($0.role) && !$0.full_name.isEmpty }
                .map(\.full_name)
                .sorted()

            let customerMap = try applyCustomers(customers, in: context)
            let jobMap = try applyJobs(jobs, customers: customerMap, in: context)
            let proposalMap = try applyProposals(proposals, jobs: jobMap, in: context)
            try applyLineItems(lineItems, proposals: proposalMap, in: context)
            let libraryIDs = try await applyLibrary(library, in: context)

            try context.save()
            state.update(
                proposals: Set(proposals.map(\.id)),
                customers: Set(customers.map(\.id)),
                jobs: Set(jobs.map(\.id)),
                lineItems: Set(lineItems.map(\.id)),
                library: libraryIDs,
                salesReps: repNames,
                syncedAt: Date()
            )
            lastError = nil
        } catch {
            // Offline or server trouble: keep what we have and try again later.
            lastError = error.localizedDescription
        }
    }

    // MARK: - Fetch helper (pages past Supabase's 1,000-row limit)

    private func fetchAll<T: Decodable & Sendable>(_ table: String, columns: String) async throws -> [T] {
        var all: [T] = []
        var from = 0
        let pageSize = 1000
        while true {
            let page: [T] = try await client
                .from(table)
                .select(columns)
                .order("id")
                .range(from: from, to: from + pageSize - 1)
                .execute()
                .value
            all.append(contentsOf: page)
            if page.count < pageSize { break }
            from += pageSize
        }
        return all
    }

    // MARK: - Company defaults (tax rate + terms used for new proposals)

    private func applyCompanyDefaults(_ org: CloudOrganization?) {
        guard let org else { return }
        let defaults = UserDefaults.standard
        defaults.set(org.default_tax_rate.value, forKey: CompanyInfo.Keys.taxRate)
        if !org.default_terms.isEmpty {
            defaults.set(org.default_terms, forKey: CompanyInfo.Keys.terms)
        }
    }

    // MARK: - Customers

    private func applyCustomers(_ rows: [CloudCustomer], in context: ModelContext) throws -> [UUID: Customer] {
        let local = try context.fetch(FetchDescriptor<Customer>())
        var byID = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for row in rows {
            let c = byID[row.id] ?? {
                let new = Customer(id: row.id)
                context.insert(new)
                return new
            }()
            c.name = row.name
            c.companyName = row.company_name
            c.email = row.email
            c.phone = row.phone
            c.street = row.street
            c.city = row.city
            c.state = row.state
            c.zip = row.zip
            byID[row.id] = c
        }

        // Remove cloud customers that were deleted on the web.
        let cloudIDs = Set(rows.map(\.id))
        for id in state.customerIDs.subtracting(cloudIDs) {
            if let c = byID[id] { context.delete(c); byID[id] = nil }
        }
        return byID
    }

    // MARK: - Jobs

    private func applyJobs(_ rows: [CloudJob], customers: [UUID: Customer], in context: ModelContext) throws -> [UUID: Job] {
        let local = try context.fetch(FetchDescriptor<Job>())
        var byID = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for row in rows {
            let j = byID[row.id] ?? {
                let new = Job(id: row.id)
                context.insert(new)
                return new
            }()
            j.title = row.title
            j.siteStreet = row.site_street
            j.siteCity = row.site_city
            j.siteState = row.site_state
            j.siteZip = row.site_zip
            j.notes = row.notes
            j.customer = row.customer_id.flatMap { customers[$0] }
            byID[row.id] = j
        }

        let cloudIDs = Set(rows.map(\.id))
        for id in state.jobIDs.subtracting(cloudIDs) {
            if let j = byID[id] { context.delete(j); byID[id] = nil }
        }
        return byID
    }

    // MARK: - Proposals

    private func applyProposals(_ rows: [CloudProposal], jobs: [UUID: Job], in context: ModelContext) throws -> [UUID: Proposal] {
        let local = try context.fetch(FetchDescriptor<Proposal>())
        var byID = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let numbersByID = Dictionary(rows.map { ($0.id, $0.number ?? "") }, uniquingKeysWith: { first, _ in first })

        for row in rows {
            let p = byID[row.id] ?? {
                let new = Proposal(id: row.id)
                context.insert(new)
                return new
            }()

            p.proposalNumber = row.number ?? ""
            if let d = Self.parseDay(row.proposal_date) { p.date = d }
            p.statusRaw = row.status
            p.divisionRaw = Self.localDivision(row.division)
            p.taxRate = row.tax_rate.value
            p.terms = row.terms
            p.scopeOfWork = row.scope_text
            p.scopeOfWorkRTF = nil   // web notes arrive as plain text for now
            p.warrantyRaw = Self.localWarranty(row.warranty)
            p.inspector = row.inspector
            p.referral = row.referral
            p.permitRequired = row.permit_required
            p.isArchived = row.is_archived
            p.supersedesProposalNumber = row.supersedes_id.flatMap { numbersByID[$0] }
            p.job = row.job_id.flatMap { jobs[$0] }

            let pdf = row.pdf_options ?? [:]
            p.showLineItemsOnPDF = pdf["show_line_items"]?.boolValue ?? true
            p.showPricingOnPDF = pdf["show_pricing"]?.boolValue ?? true
            p.showPermitOnPDF = pdf["show_permit"]?.boolValue ?? true

            Self.applyChecklist(row.scope_checklist ?? [:], to: p)
            p.updatedAt = Date()
            byID[row.id] = p
        }

        let cloudIDs = Set(rows.map(\.id))
        for id in state.proposalIDs.subtracting(cloudIDs) {
            if let p = byID[id] { context.delete(p); byID[id] = nil }
        }
        return byID
    }

    private static func applyChecklist(_ c: [String: JSONValue], to p: Proposal) {
        func flag(_ key: String) -> Bool { c[key]?.boolValue ?? false }
        func text(_ key: String) -> String { c[key]?.stringValue ?? "" }

        p.extLinealFeet = text("ext_lineal_feet")
        p.extWallsWaterproof = flag("ext_walls_waterproof")
        p.extWallsR5 = flag("ext_walls_r5")
        p.extWallsR10 = flag("ext_walls_r10")
        p.extDownspoutDrains = flag("ext_downspout_drains")
        p.extBelowGradeDrainage = flag("ext_below_grade_drainage")
        p.extACRemoval = flag("ext_ac_removal")
        p.extGravelBackfill = flag("ext_gravel_backfill")
        p.extGravelDepth = text("ext_gravel_depth")
        p.extRoughGrade = flag("ext_rough_grade")

        p.intWaterPressureRelief = flag("int_water_pressure_relief")
        p.intFullVinyl = flag("int_full_vinyl")
        p.intVinylKicker = flag("int_vinyl_kicker")
        p.intSumpPump = flag("int_sump_pump")
        p.intSumpOutside = flag("int_sump_outside")
        p.intSumpInside = flag("int_sump_inside")
        p.intCarbonFiber = flag("int_carbon_fiber")
        p.intPowerBrace = flag("int_power_brace")
        p.intHelicalPiers = flag("int_helical_piers")

        p.svcSumpPump = flag("svc_sump_pump")
        p.svcBatteryBackup = flag("svc_battery_backup")
        p.svcAnnualMaintenance = flag("svc_annual_maintenance")
        p.svcDrainCleaning = flag("svc_drain_cleaning")
        p.svcCrackRepair = flag("svc_crack_repair")
        p.svcDehumidifier = flag("svc_dehumidifier")
        p.svcWarrantyVisit = flag("svc_warranty_visit")
        p.svcOtherWork = text("svc_other_work")
    }

    // MARK: - Line items

    private func applyLineItems(_ rows: [CloudLineItem], proposals: [UUID: Proposal], in context: ModelContext) throws {
        let local = try context.fetch(FetchDescriptor<LineItem>())
        var byID = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for row in rows {
            guard let proposal = proposals[row.proposal_id] else { continue }
            if let item = byID[row.id] {
                item.descriptionText = row.description
                item.quantity = row.quantity.value
                item.unit = row.unit
                item.unitPrice = row.unit_price.value
                item.sortOrder = row.sort_order
                if item.proposal?.id != proposal.id {
                    item.proposal = proposal
                }
                item.updatedAt = Date()
            } else {
                let item = LineItem(
                    id: row.id,
                    descriptionText: row.description,
                    quantity: row.quantity.value,
                    unitPrice: row.unit_price.value,
                    unit: row.unit,
                    sortOrder: row.sort_order,
                    proposal: proposal
                )
                context.insert(item)
                proposal.lineItems.append(item)
                byID[row.id] = item
            }
        }

        let cloudIDs = Set(rows.map(\.id))
        for id in state.lineItemIDs.subtracting(cloudIDs) {
            if let item = byID[id] { context.delete(item) }
        }
    }

    // MARK: - Literature library

    /// Downloads new library PDFs, renames changed ones and removes deleted ones.
    /// Once the company library exists in the cloud, the brochures bundled in the
    /// app are retired so reps see one shared list.
    private func applyLibrary(_ rows: [CloudLibraryDocument], in context: ModelContext) async throws -> Set<UUID> {
        let local = try context.fetch(FetchDescriptor<LibraryDocument>())
        var byID = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var synced = state.libraryIDs.intersection(Set(rows.map(\.id)))

        for row in rows {
            let filename = Self.libraryFilename(for: row)
            if let doc = byID[row.id] {
                doc.title = row.title
                doc.filename = filename
                synced.insert(row.id)
                continue
            }
            do {
                let data = try await client.storage.from("eco-files").download(path: row.file_path)
                let doc = LibraryDocument(id: row.id, title: row.title, filename: filename, pdfData: data)
                context.insert(doc)
                byID[row.id] = doc
                synced.insert(row.id)
            } catch {
                // Couldn't download this one right now; try again next sync.
                continue
            }
        }

        let cloudIDs = Set(rows.map(\.id))
        for id in state.libraryIDs.subtracting(cloudIDs) {
            if let doc = byID[id] { context.delete(doc); byID[id] = nil }
        }

        if !rows.isEmpty {
            let bundled = Set(BundledLiterature.items.map(\.filename))
            for doc in local where bundled.contains(doc.filename) && !cloudIDs.contains(doc.id) {
                context.delete(doc)
            }
        }
        return synced
    }

    /// Local file name for a cloud document. The Fortress brochure keeps the name
    /// the editor's Fortress auto-attach looks for.
    private static func libraryFilename(for row: CloudLibraryDocument) -> String {
        if let rule = row.auto_attach_rule?.lowercased(), rule.hasSuffix(":fortress") {
            return BundledLiterature.fortressFilename
        }
        return row.title.hasSuffix(".pdf") ? row.title : "\(row.title).pdf"
    }

    // MARK: - Value mapping

    private static func localDivision(_ cloud: String) -> String {
        switch cloud {
        case "new_construction": return Division.newConstruction.rawValue
        case "service":          return Division.service.rawValue
        default:                 return Division.remodel.rawValue
        }
    }

    private static func localWarranty(_ cloud: String) -> String {
        switch cloud {
        case "thirty_year": return WarrantyOption.thirtyYear.rawValue
        case "lifetime":    return WarrantyOption.lifetime.rawValue
        default:            return WarrantyOption.none.rawValue
        }
    }

    private static func parseDay(_ text: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(text.prefix(10)))
    }
}
