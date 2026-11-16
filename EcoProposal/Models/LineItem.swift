import Foundation
import SwiftData

@Model
final class LineItem {
    var id: UUID
    var descriptionText: String
    var quantity: Double
    var unitPrice: Double
    /// Unit of measure — "sq ft", "lin ft", "hr", "mi", "ea", "lot", or a custom label.
    /// Shown next to the quantity on the PDF (e.g. "342.5 sq ft").
    var unit: String = "ea"
    var sortOrder: Int
    var proposal: Proposal?
    var remoteRecordID: Int?
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        descriptionText: String = "",
        quantity: Double = 1,
        unitPrice: Double = 0,
        unit: String = "ea",
        sortOrder: Int = 0,
        proposal: Proposal? = nil,
        remoteRecordID: Int? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.descriptionText = descriptionText
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.unit = unit
        self.sortOrder = sortOrder
        self.proposal = proposal
        self.remoteRecordID = remoteRecordID
        self.updatedAt = updatedAt
    }

    var lineTotal: Double {
        quantity * unitPrice
    }

    /// Common preset units the rep can pick from. "Custom" lets them type anything.
    static let presetUnits = [
        "ea", "sq ft", "lin ft", "hr", "day", "mi", "lot", "yd", "ton", "gal"
    ]
}
