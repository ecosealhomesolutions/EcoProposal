import Foundation

// Shapes of the Supabase rows the iPad downloads (Phase 3, session 2).
// Column names match the database exactly; see supabase/migrations.
// `nonisolated` because the project defaults to main-actor isolation, and these
// are decoded by the Supabase client off the main thread.

/// A number that may arrive as a JSON number or a numeric string.
nonisolated struct FlexDouble: Decodable, Sendable {
    let value: Double

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) {
            value = d
        } else if let s = try? c.decode(String.self), let d = Double(s) {
            value = d
        } else {
            value = 0
        }
    }
}

/// Any JSON value inside a jsonb column (used for the scope checklist and PDF options).
nonisolated enum JSONValue: Decodable, Sendable {
    case bool(Bool)
    case number(Double)
    case string(String)
    case null
    case other

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else {
            self = .other
        }
    }

    var boolValue: Bool {
        switch self {
        case .bool(let b): return b
        case .number(let n): return n != 0
        case .string(let s): return ["true", "1", "yes"].contains(s.lowercased())
        default: return false
        }
    }

    var stringValue: String {
        switch self {
        case .string(let s): return s
        case .number(let n):
            return n.rounded() == n ? String(Int(n)) : String(n)
        case .bool(let b): return b ? "true" : "false"
        default: return ""
        }
    }
}

nonisolated struct CloudOrganization: Decodable, Sendable {
    let id: UUID
    let default_tax_rate: FlexDouble
    let default_terms: String
}

nonisolated struct CloudProfileRow: Decodable, Sendable {
    let id: UUID
    let full_name: String
    let role: String
    let active: Bool
}

nonisolated struct CloudCustomer: Decodable, Sendable {
    let id: UUID
    let name: String
    let company_name: String?
    let email: String?
    let phone: String?
    let street: String?
    let city: String?
    let state: String?
    let zip: String?
}

nonisolated struct CloudJob: Decodable, Sendable {
    let id: UUID
    let customer_id: UUID?
    let title: String
    let site_street: String?
    let site_city: String?
    let site_state: String?
    let site_zip: String?
    let notes: String?
}

nonisolated struct CloudProposal: Decodable, Sendable {
    let id: UUID
    let job_id: UUID?
    let number: String?
    let proposal_date: String
    let division: String
    let status: String
    let tax_rate: FlexDouble
    let terms: String
    let scope_text: String
    let scope_checklist: [String: JSONValue]?
    let warranty: String
    let inspector: String
    let referral: String
    let permit_required: Bool
    let pdf_options: [String: JSONValue]?
    let is_archived: Bool
    let supersedes_id: UUID?
    let locked_at: String?
}

nonisolated struct CloudLineItem: Decodable, Sendable {
    let id: UUID
    let proposal_id: UUID
    let description: String
    let quantity: FlexDouble
    let unit: String
    let unit_price: FlexDouble
    let sort_order: Int
}

nonisolated struct CloudLibraryDocument: Decodable, Sendable {
    let id: UUID
    let title: String
    let file_path: String
    let auto_attach_rule: String?
}
