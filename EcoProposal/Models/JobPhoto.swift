import Foundation
import SwiftData

@Model
final class JobPhoto {
    var id: UUID
    var caption: String
    var sortOrder: Int
    var createdAt: Date
    var proposal: Proposal?
    /// Set instead of `proposal` when the photo documents an inspection report.
    var inspection: InspectionReport?

    /// Stored externally so the SwiftData store stays lean when photos accumulate.
    @Attribute(.externalStorage) var imageData: Data

    /// PKDrawing bytes for pen/pencil markup layered on top of the photo.
    /// Rendered together with `imageData` on the PDF; nil until the rep draws.
    var annotationData: Data?

    var remoteRecordID: Int?
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        imageData: Data,
        caption: String = "",
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        proposal: Proposal? = nil,
        remoteRecordID: Int? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.imageData = imageData
        self.caption = caption
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.proposal = proposal
        self.remoteRecordID = remoteRecordID
        self.updatedAt = updatedAt
    }
}
