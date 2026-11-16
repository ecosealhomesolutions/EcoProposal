import Foundation
import SwiftData

/// A piece of job-related literature (brochure, spec sheet, warranty doc, etc.)
/// attached to a specific proposal. Holds its own copy of the PDF bytes so the
/// proposal stays self-contained — deleting a library item or editing it later
/// never changes what was attached to (or already sent with) a proposal.
///
/// Attached documents are merged onto the end of the generated proposal PDF, so
/// they travel with the proposal through every send channel (Mail, Share, OneDrive).
@Model
final class ProposalDocument {
    var id: UUID
    /// Display name shown in the editor list (defaults to the file name).
    var title: String
    /// Original file name, kept for reference/export.
    var filename: String
    var sortOrder: Int
    var createdAt: Date
    var proposal: Proposal?

    /// Raw PDF bytes, stored externally so the SwiftData store stays lean.
    @Attribute(.externalStorage) var pdfData: Data

    init(
        id: UUID = UUID(),
        title: String,
        filename: String,
        pdfData: Data,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        proposal: Proposal? = nil
    ) {
        self.id = id
        self.title = title
        self.filename = filename
        self.pdfData = pdfData
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.proposal = proposal
    }
}

/// A reusable document in the company-wide literature library. Reps add brochures
/// once (in Settings → Document library), then attach them to any proposal without
/// re-importing the file each time. Attaching copies the bytes into a
/// `ProposalDocument`, so the two are independent after attachment.
@Model
final class LibraryDocument {
    var id: UUID
    var title: String
    var filename: String
    var createdAt: Date

    @Attribute(.externalStorage) var pdfData: Data

    init(
        id: UUID = UUID(),
        title: String,
        filename: String,
        pdfData: Data,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.filename = filename
        self.pdfData = pdfData
        self.createdAt = createdAt
    }
}
