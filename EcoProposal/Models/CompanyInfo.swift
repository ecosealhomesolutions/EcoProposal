import Foundation

/// Company branding shown on every proposal PDF.
///
/// Identity fields (name, address, phone, website) are baked into the app as
/// constants — reps can't edit them, matching how OneDrive credentials work.
/// Tax rate + default terms remain UserDefaults-backed so the admin can still
/// tune those from Settings → Proposal Defaults.
struct CompanyInfo: Equatable {
    // MARK: - Constants (edit here + rebuild to change)

    let name = "Eco-Seal Home Solutions"
    let street = "3530 County Road 58"
    let cityStateZip = "Millersburg, OH 44654"
    let phone = "330.893.7325"
    let website = "ecosealsolutions.com"

    /// Convenience — full address as a single string for older callsites.
    var address: String { "\(street)\n\(cityStateZip)" }

    // MARK: - UserDefaults-backed defaults

    var defaultTaxRate: Double
    var defaultTerms: String

    static let fallbackTerms = "20% deposit due upon acceptance. Balance due upon project completion. Prices valid for 30 days from proposal date."

    enum Keys {
        static let taxRate = "company.taxRate"
        static let terms   = "company.terms"
        static let seq     = "company.proposalSeq"
    }

    static func load(from defaults: UserDefaults = .standard) -> CompanyInfo {
        CompanyInfo(
            defaultTaxRate: defaults.object(forKey: Keys.taxRate) as? Double ?? 0,
            defaultTerms: defaults.string(forKey: Keys.terms) ?? CompanyInfo.fallbackTerms
        )
    }

    /// Increments the persistent proposal counter and returns the next display number, e.g. "P-2026-0001".
    static func nextProposalNumber(on date: Date = Date(), defaults: UserDefaults = .standard) -> String {
        let next = defaults.integer(forKey: Keys.seq) + 1
        defaults.set(next, forKey: Keys.seq)
        let year = Calendar.current.component(.year, from: date)
        return String(format: "P-%04d-%04d", year, next)
    }
}
