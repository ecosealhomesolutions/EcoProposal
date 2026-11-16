import Foundation
import Observation
import SwiftData
import CryptoKit
import Supabase

/// Two-way sync between the iPad's local database and EcoProposal Cloud
/// (Phase 3, sessions 2–3).
///
/// How it decides what to do:
/// - Every linked record has a "fingerprint" of what was last exchanged with the
///   cloud. If the iPad's copy no longer matches, the rep edited it here, so it
///   is uploaded and never overwritten by a download.
/// - Proposals are uploaded with the version number the iPad last saw. If the
///   website changed it in the meantime, the upload is refused and the proposal
///   is flagged as a conflict for the rep to resolve.
/// - New proposals made here upload automatically; the database assigns the
///   number (or keeps the iPad's old number, adding initials if it's taken).
/// - Offline: nothing is lost. Unsent edits stay "dirty" and go up on the next
///   successful attempt.
/// Timing: upload 2 s after a save and every 20 s; download at launch, on return
/// to the app, every 2 minutes and on pull-to-refresh.
@MainActor
@Observable
final class CloudSync {
    static let shared = CloudSync()

    private(set) var isSyncing = false
    private(set) var lastError: String?
    /// Proposals edited on both the iPad and the website since the last sync.
    private(set) var conflicts: Set<UUID> = []
    private(set) var profile: CloudProfile?

    /// True once the rep is signed in to EcoProposal Cloud on this iPad.
    var isActive: Bool { context != nil && profile != nil }

    // Internal (not private) so the file-sync extension in CloudFileSync.swift can use them.
    @ObservationIgnored let client = SupabaseService.client
    @ObservationIgnored let state = CloudSyncState.shared
    @ObservationIgnored private(set) var context: ModelContext?
    @ObservationIgnored private var autoSyncTask: Task<Void, Never>?
    @ObservationIgnored private var pushDebounce: Task<Void, Never>?
    @ObservationIgnored private var saveObserver: NSObjectProtocol?

    private init() {}

    // MARK: - Scheduling

    func startAutoSync(context: ModelContext, profile: CloudProfile?) {
        self.context = context
        self.profile = profile
        guard autoSyncTask == nil else { return }

        autoSyncTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                if tick % 6 == 0 { await self?.pullNow() }   // every 2 minutes
                await self?.pushNow()                         // every 20 seconds
                tick += 1
                try? await Task.sleep(for: .seconds(20))
            }
        }

        saveObserver = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.schedulePush() }
        }
    }

    func stopAutoSync() {
        autoSyncTask?.cancel()
        autoSyncTask = nil
        pushDebounce?.cancel()
        if let saveObserver { NotificationCenter.default.removeObserver(saveObserver) }
        saveObserver = nil
        profile = nil
    }

    /// Upload a couple of seconds after the last save.
    func schedulePush() {
        guard isActive else { return }
        pushDebounce?.cancel()
        pushDebounce = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.pushNow()
        }
    }

    /// Pull-to-refresh / "Sync now": send local edits first, then download.
    func syncNow() async {
        await pushNow()
        await pullNow()
    }

    // MARK: - Permissions (mirror the database rules)

    /// Whether this rep may edit a proposal on the iPad. Proposals that only
    /// exist on this iPad are always editable.
    func canEdit(_ id: UUID) -> Bool {
        let st = state.stored
        guard st.proposalIDs.contains(id) else { return true }
        if st.lockedProposalIDs.contains(id) { return false }
        guard let profile else { return false }
        switch profile.role {
        case "admin", "manager":
            return true
        case "sales_rep":
            return st.proposalOwners[id] == profile.id
                || (st.proposalCollaborators[id] ?? []).contains(profile.id)
        default:
            return false
        }
    }

    func isLockedInCloud(_ id: UUID) -> Bool {
        state.stored.lockedProposalIDs.contains(id)
    }

    // MARK: - Conflict resolution

    /// Send the iPad's copy over the website's newer version.
    func keepIPadVersion(_ id: UUID) async {
        if let rows: [CloudVersionRow] = try? await client
            .from("proposals").select("id, version, locked_at")
            .eq("id", value: id.uuidString).execute().value,
           let row = rows.first {
            state.stored.proposalVersions[id] = row.version
        }
        conflicts.remove(id)
        state.save()
        await pushNow()
    }

    /// Throw away the iPad's edits and take the website's version.
    func useWebsiteVersion(_ id: UUID) async {
        conflicts.remove(id)
        if let context, let p = Self.fetchProposal(id, in: context) {
            state.stored.proposalFingerprints[id] = proposalFingerprint(p, numberToID: localNumberMap(in: context))
            state.stored.notesFingerprints[id] = Self.notesFingerprint(p)
            state.stored.scopeHTMLHashes[id] = nil
        }
        state.save()
        await pullNow()
    }

    // MARK: - Download

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
                columns: "id, owner_id, collaborator_ids, version, scope_html, job_id, number, proposal_date, division, status, tax_rate, terms, scope_text, scope_checklist, warranty, inspector, referral, permit_required, pdf_options, is_archived, supersedes_id, locked_at"
            )
            let lineItems: [CloudLineItem] = try await fetchAll("line_items", columns: "id, proposal_id, description, quantity, unit, unit_price, sort_order")
            let library: [CloudLibraryDocument] = try await fetchAll("library_documents", columns: "id, title, file_path, auto_attach_rule")

            applyCompanyDefaults(org.first)
            state.stored.salesRepNames = profiles
                .filter { $0.active && ["sales_rep", "manager", "admin"].contains($0.role) && !$0.full_name.isEmpty }
                .map(\.full_name)
                .sorted()

            let customerMap = try applyCustomers(customers, in: context)
            let jobMap = try applyJobs(jobs, customers: customerMap, in: context)
            let (proposalMap, applied) = try applyProposals(proposals, jobs: jobMap, in: context)
            try applyLineItems(lineItems, proposals: proposalMap, applied: applied, in: context)

            // Remember exactly what we now hold for every proposal we updated.
            let numbers = localNumberMap(in: context)
            for id in applied {
                guard let p = proposalMap[id] else { continue }
                state.stored.proposalFingerprints[id] = proposalFingerprint(p, numberToID: numbers)
                state.stored.notesFingerprints[id] = Self.notesFingerprint(p)
                state.stored.proposalLineItemIDs[id] = p.lineItems.map(\.id)
            }

            // Session 4: photos, sketches, signatures and attached PDFs
            try await pullFiles(proposals: proposalMap, applied: applied, in: context)

            state.stored.libraryIDs = try await applyLibrary(library, in: context)
            state.stored.lastSyncedAt = Date()

            try context.save()
            state.save()
            lastError = nil
        } catch {
            // Offline or server trouble: keep what we have and try again later.
            lastError = error.localizedDescription
        }
    }

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

    private func applyCompanyDefaults(_ org: CloudOrganization?) {
        guard let org else { return }
        let defaults = UserDefaults.standard
        defaults.set(org.default_tax_rate.value, forKey: CompanyInfo.Keys.taxRate)
        if !org.default_terms.isEmpty {
            defaults.set(org.default_terms, forKey: CompanyInfo.Keys.terms)
        }
    }

    // Customers
    private func applyCustomers(_ rows: [CloudCustomer], in context: ModelContext) throws -> [UUID: Customer] {
        let local = try context.fetch(FetchDescriptor<Customer>())
        var byID = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for row in rows {
            if let existing = byID[row.id], isDirty(existing) { continue }  // unsent iPad edit wins
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
            state.stored.customerFingerprints[row.id] = Self.fingerprint(customerPayload(c))
        }

        let cloudIDs = Set(rows.map(\.id))
        for id in state.stored.customerIDs.subtracting(cloudIDs) {
            if let c = byID[id] { context.delete(c); byID[id] = nil }
            state.stored.customerFingerprints[id] = nil
        }
        state.stored.customerIDs = cloudIDs
        return byID
    }

    // Jobs
    private func applyJobs(_ rows: [CloudJob], customers: [UUID: Customer], in context: ModelContext) throws -> [UUID: Job] {
        let local = try context.fetch(FetchDescriptor<Job>())
        var byID = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for row in rows {
            if let existing = byID[row.id], isDirty(existing) { continue }
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
            state.stored.jobFingerprints[row.id] = Self.fingerprint(jobPayload(j))
        }

        let cloudIDs = Set(rows.map(\.id))
        for id in state.stored.jobIDs.subtracting(cloudIDs) {
            if let j = byID[id] { context.delete(j); byID[id] = nil }
            state.stored.jobFingerprints[id] = nil
        }
        state.stored.jobIDs = cloudIDs
        return byID
    }

    // Proposals — returns all local proposals by id, plus the ids that were updated from the cloud.
    private func applyProposals(_ rows: [CloudProposal], jobs: [UUID: Job], in context: ModelContext) throws -> ([UUID: Proposal], Set<UUID>) {
        let local = try context.fetch(FetchDescriptor<Proposal>())
        var byID = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let numbersByID = Dictionary(rows.map { ($0.id, $0.number ?? "") }, uniquingKeysWith: { first, _ in first })
        var applied = Set<UUID>()
        let numbers = localNumberMap(in: context)

        for row in rows {
            // Permissions and lock state always follow the cloud.
            state.stored.proposalOwners[row.id] = row.owner_id
            state.stored.proposalCollaborators[row.id] = row.collaborator_ids ?? []
            if row.locked_at != nil {
                state.stored.lockedProposalIDs.insert(row.id)
            } else {
                state.stored.lockedProposalIDs.remove(row.id)
            }

            if let existing = byID[row.id], state.stored.proposalIDs.contains(row.id), isDirty(existing, numbers: numbers) {
                // The rep has unsent edits. Keep them; flag a conflict if the website changed it too.
                if row.version > (state.stored.proposalVersions[row.id] ?? 0) {
                    conflicts.insert(row.id)
                }
                continue
            }

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
            if let html = row.scope_html, !html.isEmpty {
                let h = Self.hash(Data(html.utf8))
                if state.stored.scopeHTMLHashes[row.id] != h {
                    p.scopeOfWorkRTF = RichTextBridge.rtf(fromHTML: html)
                    state.stored.scopeHTMLHashes[row.id] = h
                }
            } else {
                p.scopeOfWorkRTF = nil
                state.stored.scopeHTMLHashes[row.id] = nil
            }
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
            applied.insert(row.id)
            state.stored.proposalVersions[row.id] = row.version
            conflicts.remove(row.id)
        }

        // Proposals deleted on the website
        let cloudIDs = Set(rows.map(\.id))
        for id in state.stored.proposalIDs.subtracting(cloudIDs) {
            if let p = byID[id] { context.delete(p); byID[id] = nil }
            state.stored.proposalFingerprints[id] = nil
            state.stored.proposalVersions[id] = nil
            state.stored.proposalLineItemIDs[id] = nil
            conflicts.remove(id)
        }
        state.stored.proposalIDs = cloudIDs
        return (byID, applied)
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

    // Line items — the cloud is the truth for every proposal that was just updated from it.
    private func applyLineItems(_ rows: [CloudLineItem], proposals: [UUID: Proposal], applied: Set<UUID>, in context: ModelContext) throws {
        let local = try context.fetch(FetchDescriptor<LineItem>())
        var byID = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var keep = Set<UUID>()

        for row in rows where applied.contains(row.proposal_id) {
            guard let proposal = proposals[row.proposal_id] else { continue }
            keep.insert(row.id)
            if let item = byID[row.id] {
                item.descriptionText = row.description
                item.quantity = row.quantity.value
                item.unit = row.unit
                item.unitPrice = row.unit_price.value
                item.sortOrder = row.sort_order
                if item.proposal?.id != proposal.id { item.proposal = proposal }
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

        for id in applied {
            guard let proposal = proposals[id] else { continue }
            for item in proposal.lineItems where !keep.contains(item.id) {
                context.delete(item)
            }
        }
    }

    // Literature library (download only; admins manage it on the website)
    private func applyLibrary(_ rows: [CloudLibraryDocument], in context: ModelContext) async throws -> Set<UUID> {
        let local = try context.fetch(FetchDescriptor<LibraryDocument>())
        var byID = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var synced = state.stored.libraryIDs.intersection(Set(rows.map(\.id)))

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
                continue  // try again next sync
            }
        }

        let cloudIDs = Set(rows.map(\.id))
        for id in state.stored.libraryIDs.subtracting(cloudIDs) {
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

    private static func libraryFilename(for row: CloudLibraryDocument) -> String {
        if let rule = row.auto_attach_rule?.lowercased(), rule.hasSuffix(":fortress") {
            return BundledLiterature.fortressFilename
        }
        return row.title.hasSuffix(".pdf") ? row.title : "\(row.title).pdf"
    }

    // MARK: - Upload

    func pushNow() async {
        guard let context, let profile, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        var firstError: String?
        func note(_ error: Error) { if firstError == nil { firstError = error.localizedDescription } }

        // 1. Customers
        for c in (try? context.fetch(FetchDescriptor<Customer>())) ?? [] {
            let payload = customerPayload(c)
            let fp = Self.fingerprint(payload)
            let tracked = state.stored.customerIDs.contains(c.id)
            if tracked && (state.stored.customerFingerprints[c.id] ?? fp) == fp { continue }
            do {
                if tracked {
                    try await client.from("customers").update(payload).eq("id", value: c.id.uuidString).execute()
                } else {
                    var insert = payload
                    insert.org_id = profile.orgId
                    insert.owner_id = profile.id
                    try await client.from("customers").insert(insert).execute()
                    state.stored.customerIDs.insert(c.id)
                }
                state.stored.customerFingerprints[c.id] = fp
            } catch { note(error) }
        }

        // 2. Jobs (only once their customer is in the cloud)
        for j in (try? context.fetch(FetchDescriptor<Job>())) ?? [] {
            if let customer = j.customer, !state.stored.customerIDs.contains(customer.id) { continue }
            let payload = jobPayload(j)
            let fp = Self.fingerprint(payload)
            let tracked = state.stored.jobIDs.contains(j.id)
            if tracked && (state.stored.jobFingerprints[j.id] ?? fp) == fp { continue }
            do {
                if tracked {
                    try await client.from("jobs").update(payload).eq("id", value: j.id.uuidString).execute()
                } else {
                    var insert = payload
                    insert.org_id = profile.orgId
                    insert.owner_id = profile.id
                    try await client.from("jobs").insert(insert).execute()
                    state.stored.jobIDs.insert(j.id)
                }
                state.stored.jobFingerprints[j.id] = fp
            } catch { note(error) }
        }

        // 3. Proposals + line items
        let proposals = (try? context.fetch(FetchDescriptor<Proposal>())) ?? []
        let numbers = Dictionary(
            proposals.filter { !$0.proposalNumber.isEmpty }.map { ($0.proposalNumber, $0.id) },
            uniquingKeysWith: { first, _ in first }
        )
        for p in proposals {
            let tracked = state.stored.proposalIDs.contains(p.id)
            let fp = proposalFingerprint(p, numberToID: numbers)
            if tracked && (state.stored.proposalFingerprints[p.id] ?? fp) == fp { continue }
            if conflicts.contains(p.id) { continue }
            if tracked && !canEdit(p.id) { continue }
            if let job = p.job, !state.stored.jobIDs.contains(job.id) { continue }
            do {
                try await pushProposal(p, tracked: tracked, fingerprint: fp, numbers: numbers, profile: profile)
            } catch { note(error) }
        }

        // 4. Files for every proposal that now exists in the cloud (signatures last: they lock it)
        for p in proposals where state.stored.proposalIDs.contains(p.id) && canEdit(p.id) && !conflicts.contains(p.id) {
            do {
                try await pushFiles(for: p, profile: profile)
            } catch { note(error) }
        }

        try? context.save()
        state.save()
        if let firstError { lastError = firstError } else if lastError != nil { lastError = nil }
    }

    private func pushProposal(_ p: Proposal, tracked: Bool, fingerprint fp: String, numbers: [String: UUID], profile: CloudProfile) async throws {
        let notesFP = Self.notesFingerprint(p)
        let notesChanged = !tracked || state.stored.notesFingerprints[p.id] != notesFP
        var payload = proposalPayload(p, includeNotes: notesChanged, numberToID: numbers)

        let ack: CloudProposalAck
        if tracked {
            let known = state.stored.proposalVersions[p.id] ?? 1
            let rows: [CloudProposalAck] = try await client
                .from("proposals")
                .update(payload)
                .eq("id", value: p.id.uuidString)
                .eq("version", value: known)
                .select("id, number, version, locked_at")
                .execute()
                .value
            guard let row = rows.first else {
                // Refused: either the website changed it (conflict) or it's locked / not ours.
                let current: [CloudVersionRow] = try await client
                    .from("proposals").select("id, version, locked_at")
                    .eq("id", value: p.id.uuidString).execute().value
                if let cur = current.first {
                    if cur.locked_at != nil {
                        state.stored.lockedProposalIDs.insert(p.id)
                    } else if cur.version != known {
                        conflicts.insert(p.id)
                    }
                }
                return
            }
            ack = row
        } else {
            payload.org_id = profile.orgId
            payload.owner_id = profile.id
            payload.number = p.proposalNumber.isEmpty ? nil : p.proposalNumber
            let rows: [CloudProposalAck] = try await client
                .from("proposals")
                .insert(payload)
                .select("id, number, version, locked_at")
                .execute()
                .value
            guard let row = rows.first else { return }
            ack = row
            state.stored.proposalIDs.insert(p.id)
            state.stored.proposalOwners[p.id] = profile.id
        }

        if let number = ack.number, !number.isEmpty, number != p.proposalNumber {
            p.proposalNumber = number
        }
        state.stored.proposalVersions[p.id] = ack.version

        // Line items: upsert what's here, delete what was removed here.
        let items = p.lineItems.map { lineItemPayload($0, proposalID: p.id) }
        if !items.isEmpty {
            try await client.from("line_items").upsert(items, onConflict: "id").execute()
        }
        let current = Set(items.map(\.id))
        let removed = Set(state.stored.proposalLineItemIDs[p.id] ?? []).subtracting(current)
        if !removed.isEmpty {
            try await client.from("line_items").delete().in("id", values: removed.map(\.uuidString)).execute()
        }

        state.stored.proposalLineItemIDs[p.id] = Array(current)
        state.stored.notesFingerprints[p.id] = notesFP
        if notesChanged, let html = payload.scope_html {
            state.stored.scopeHTMLHashes[p.id] = Self.hash(Data(html.utf8))
        }
        // The fingerprint of what was sent (not of the live model, which the rep may still be typing into).
        state.stored.proposalFingerprints[p.id] = fp
    }

    // MARK: - Payloads

    private func customerPayload(_ c: Customer) -> CustomerPayload {
        CustomerPayload(
            id: c.id, org_id: nil, owner_id: nil,
            name: c.name, company_name: c.companyName, email: c.email, phone: c.phone,
            street: c.street, city: c.city, state: c.state, zip: c.zip
        )
    }

    private func jobPayload(_ j: Job) -> JobPayload {
        JobPayload(
            id: j.id, org_id: nil, owner_id: nil, customer_id: j.customer?.id,
            title: j.title, site_street: j.siteStreet, site_city: j.siteCity,
            site_state: j.siteState, site_zip: j.siteZip, notes: j.notes
        )
    }

    private func lineItemPayload(_ item: LineItem, proposalID: UUID) -> LineItemPayload {
        LineItemPayload(
            id: item.id, proposal_id: proposalID, description: item.descriptionText,
            quantity: item.quantity, unit: item.unit, unit_price: item.unitPrice, sort_order: item.sortOrder
        )
    }

    private func proposalPayload(_ p: Proposal, includeNotes: Bool, numberToID: [String: UUID]) -> ProposalPayload {
        var checklist: [String: AnyJSON] = [
            "ext_lineal_feet": .string(p.extLinealFeet),
            "ext_walls_waterproof": .bool(p.extWallsWaterproof),
            "ext_walls_r5": .bool(p.extWallsR5),
            "ext_walls_r10": .bool(p.extWallsR10),
            "ext_downspout_drains": .bool(p.extDownspoutDrains),
            "ext_below_grade_drainage": .bool(p.extBelowGradeDrainage),
            "ext_ac_removal": .bool(p.extACRemoval),
            "ext_gravel_backfill": .bool(p.extGravelBackfill),
            "ext_gravel_depth": .string(p.extGravelDepth),
            "ext_rough_grade": .bool(p.extRoughGrade),
            "int_water_pressure_relief": .bool(p.intWaterPressureRelief),
            "int_full_vinyl": .bool(p.intFullVinyl),
            "int_vinyl_kicker": .bool(p.intVinylKicker),
            "int_sump_pump": .bool(p.intSumpPump),
            "int_sump_outside": .bool(p.intSumpOutside),
            "int_sump_inside": .bool(p.intSumpInside),
            "int_carbon_fiber": .bool(p.intCarbonFiber),
            "int_power_brace": .bool(p.intPowerBrace),
            "int_helical_piers": .bool(p.intHelicalPiers),
        ]
        checklist["svc_sump_pump"] = .bool(p.svcSumpPump)
        checklist["svc_battery_backup"] = .bool(p.svcBatteryBackup)
        checklist["svc_annual_maintenance"] = .bool(p.svcAnnualMaintenance)
        checklist["svc_drain_cleaning"] = .bool(p.svcDrainCleaning)
        checklist["svc_crack_repair"] = .bool(p.svcCrackRepair)
        checklist["svc_dehumidifier"] = .bool(p.svcDehumidifier)
        checklist["svc_warranty_visit"] = .bool(p.svcWarrantyVisit)
        checklist["svc_other_work"] = .string(p.svcOtherWork)

        let supersedes = p.supersedesProposalNumber.flatMap { numberToID[$0] }

        return ProposalPayload(
            id: p.id,
            org_id: nil,
            owner_id: nil,
            number: nil,
            job_id: p.job?.id,
            proposal_date: Self.dayString(p.date),
            division: Self.cloudDivision(p.divisionRaw),
            status: p.statusRaw,
            tax_rate: p.taxRate,
            terms: p.terms,
            scope_text: includeNotes ? p.scopeOfWork : nil,
            scope_html: includeNotes ? RichTextBridge.html(fromRTF: p.scopeOfWorkRTF, plainText: p.scopeOfWork) : nil,
            scope_checklist: checklist,
            warranty: Self.cloudWarranty(p.warrantyRaw),
            inspector: p.inspector,
            referral: p.referral,
            permit_required: p.permitRequired,
            pdf_options: [
                "show_line_items": .bool(p.showLineItemsOnPDF),
                "show_pricing": .bool(p.showPricingOnPDF),
                "show_permit": .bool(p.showPermitOnPDF),
            ],
            is_archived: p.isArchived,
            supersedes_id: supersedes
        )
    }

    // MARK: - Fingerprints

    private nonisolated struct ProposalFingerprintBody: Encodable {
        let header: ProposalPayload
        let notes: String
        let lines: [LineItemPayload]
    }

    private func proposalFingerprint(_ p: Proposal, numberToID: [String: UUID]) -> String {
        let lines = p.lineItems
            .map { lineItemPayload($0, proposalID: p.id) }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        return Self.fingerprint(ProposalFingerprintBody(
            header: proposalPayload(p, includeNotes: false, numberToID: numberToID),
            notes: Self.notesFingerprint(p),
            lines: lines
        ))
    }

    private static func notesFingerprint(_ p: Proposal) -> String {
        var data = Data(p.scopeOfWork.utf8)
        data.append(p.scopeOfWorkRTF ?? Data())
        return hash(data)
    }

    private func isDirty(_ c: Customer) -> Bool {
        guard let stored = state.stored.customerFingerprints[c.id] else { return false }
        return stored != Self.fingerprint(customerPayload(c))
    }

    private func isDirty(_ j: Job) -> Bool {
        guard let stored = state.stored.jobFingerprints[j.id] else { return false }
        return stored != Self.fingerprint(jobPayload(j))
    }

    private func isDirty(_ p: Proposal, numbers: [String: UUID]) -> Bool {
        guard let stored = state.stored.proposalFingerprints[p.id] else { return false }
        return stored != proposalFingerprint(p, numberToID: numbers)
    }

    private func localNumberMap(in context: ModelContext) -> [String: UUID] {
        let all = (try? context.fetch(FetchDescriptor<Proposal>())) ?? []
        return Dictionary(
            all.filter { !$0.proposalNumber.isEmpty }.map { ($0.proposalNumber, $0.id) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    static func fingerprint<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return hash((try? encoder.encode(value)) ?? Data())
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func fetchProposal(_ id: UUID, in context: ModelContext) -> Proposal? {
        var descriptor = FetchDescriptor<Proposal>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    // MARK: - Value mapping (iPad ⇄ database spellings)

    private static func localDivision(_ cloud: String) -> String {
        switch cloud {
        case "new_construction": return Division.newConstruction.rawValue
        case "service":          return Division.service.rawValue
        default:                 return Division.remodel.rawValue
        }
    }

    private static func cloudDivision(_ local: String) -> String {
        switch Division(rawValue: local) ?? .remodel {
        case .newConstruction: return "new_construction"
        case .service:         return "service"
        case .remodel:         return "remodel"
        }
    }

    private static func localWarranty(_ cloud: String) -> String {
        switch cloud {
        case "thirty_year": return WarrantyOption.thirtyYear.rawValue
        case "lifetime":    return WarrantyOption.lifetime.rawValue
        default:            return WarrantyOption.none.rawValue
        }
    }

    private static func cloudWarranty(_ local: String) -> String {
        switch WarrantyOption(rawValue: local) ?? .none {
        case .thirtyYear: return "thirty_year"
        case .lifetime:   return "lifetime"
        case .none:       return "none"
        }
    }

    private static func dayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private static func parseDay(_ text: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(text.prefix(10)))
    }
}
