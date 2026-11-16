import Foundation
import SwiftData

@Model
final class Customer {
    var id: UUID
    var name: String
    var companyName: String?
    var email: String?
    var phone: String?
    var street: String?
    var city: String?
    var state: String?
    var zip: String?
    var remoteRecordID: Int?
    var updatedAt: Date

    @Relationship(inverse: \Job.customer)
    var jobs: [Job] = []

    init(
        id: UUID = UUID(),
        name: String = "",
        companyName: String? = nil,
        email: String? = nil,
        phone: String? = nil,
        street: String? = nil,
        city: String? = nil,
        state: String? = nil,
        zip: String? = nil,
        remoteRecordID: Int? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.companyName = companyName
        self.email = email
        self.phone = phone
        self.street = street
        self.city = city
        self.state = state
        self.zip = zip
        self.remoteRecordID = remoteRecordID
        self.updatedAt = updatedAt
    }

    var displayName: String {
        if let company = companyName, !company.isEmpty {
            return name.isEmpty ? company : "\(name) — \(company)"
        }
        return name.isEmpty ? "Unnamed Customer" : name
    }

    /// Multi-line address formatted for display / PDF: "Street\nCity, State  ZIP".
    /// Returns nil when nothing is filled in.
    var formattedAddress: String? {
        var lines: [String] = []
        if let street, !street.isEmpty { lines.append(street) }

        var cityStateZip: [String] = []
        var cityStateSegment = ""
        if let city, !city.isEmpty { cityStateSegment = city }
        if let state, !state.isEmpty {
            cityStateSegment = cityStateSegment.isEmpty ? state : "\(cityStateSegment), \(state)"
        }
        if !cityStateSegment.isEmpty { cityStateZip.append(cityStateSegment) }
        if let zip, !zip.isEmpty { cityStateZip.append(zip) }
        let combinedCityStateZip = cityStateZip.joined(separator: "  ")
        if !combinedCityStateZip.isEmpty { lines.append(combinedCityStateZip) }

        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}
