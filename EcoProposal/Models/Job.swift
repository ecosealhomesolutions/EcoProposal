import Foundation
import SwiftData

@Model
final class Job {
    var id: UUID
    var title: String
    var siteStreet: String?
    var siteCity: String?
    var siteState: String?
    var siteZip: String?
    var notes: String?
    var customer: Customer?
    var remoteRecordID: Int?
    var updatedAt: Date

    @Relationship(inverse: \Proposal.job)
    var proposals: [Proposal] = []

    init(
        id: UUID = UUID(),
        title: String = "",
        siteStreet: String? = nil,
        siteCity: String? = nil,
        siteState: String? = nil,
        siteZip: String? = nil,
        notes: String? = nil,
        customer: Customer? = nil,
        remoteRecordID: Int? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.siteStreet = siteStreet
        self.siteCity = siteCity
        self.siteState = siteState
        self.siteZip = siteZip
        self.notes = notes
        self.customer = customer
        self.remoteRecordID = remoteRecordID
        self.updatedAt = updatedAt
    }

    /// Multi-line site address: "Street\nCity, State  ZIP" — same format as Customer.
    var formattedSiteAddress: String? {
        var lines: [String] = []
        if let siteStreet, !siteStreet.isEmpty { lines.append(siteStreet) }

        var cityStateSegment = ""
        if let siteCity, !siteCity.isEmpty { cityStateSegment = siteCity }
        if let siteState, !siteState.isEmpty {
            cityStateSegment = cityStateSegment.isEmpty ? siteState : "\(cityStateSegment), \(siteState)"
        }
        var tail = cityStateSegment
        if let siteZip, !siteZip.isEmpty {
            tail = tail.isEmpty ? siteZip : "\(tail)  \(siteZip)"
        }
        if !tail.isEmpty { lines.append(tail) }

        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}
