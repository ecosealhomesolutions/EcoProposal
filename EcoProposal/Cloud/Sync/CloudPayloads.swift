import Foundation
import Supabase

// Rows the iPad sends to EcoProposal Cloud (Phase 3, session 3).
// Optional fields left nil are omitted from the request, so an update never
// touches columns it doesn't mention (org, owner, number are insert-only).
// `nonisolated` because the project defaults to main-actor isolation and the
// Supabase client encodes these off the main thread.

nonisolated struct CustomerPayload: Encodable, Sendable, Equatable {
    var id: UUID
    var org_id: UUID?
    var owner_id: UUID?
    var name: String
    var company_name: String?
    var email: String?
    var phone: String?
    var street: String?
    var city: String?
    var state: String?
    var zip: String?
}

nonisolated struct JobPayload: Encodable, Sendable, Equatable {
    var id: UUID
    var org_id: UUID?
    var owner_id: UUID?
    var customer_id: UUID?
    var title: String
    var site_street: String?
    var site_city: String?
    var site_state: String?
    var site_zip: String?
    var notes: String?
}

nonisolated struct ProposalPayload: Encodable, Sendable {
    var id: UUID
    var org_id: UUID?
    var owner_id: UUID?
    var number: String?
    var job_id: UUID?
    var proposal_date: String
    var division: String
    var status: String
    var tax_rate: Double
    var terms: String
    var scope_text: String?
    var scope_html: String?
    var scope_checklist: [String: AnyJSON]
    var warranty: String
    var inspector: String
    var referral: String
    var permit_required: Bool
    var pdf_options: [String: AnyJSON]
    var is_archived: Bool
    var supersedes_id: UUID?
}

nonisolated struct LineItemPayload: Encodable, Sendable, Equatable {
    var id: UUID
    var proposal_id: UUID
    var description: String
    var quantity: Double
    var unit: String
    var unit_price: Double
    var sort_order: Int
}
