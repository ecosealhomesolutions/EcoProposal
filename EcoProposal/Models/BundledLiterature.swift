import Foundation
import SwiftData

/// Brochures shipped inside the app bundle (Resources/Literature). On launch they
/// are seeded into the shared literature library so every rep has the standard
/// sales literature available with zero setup.
///
/// Seeding is idempotent: a bundled document is only inserted when no library
/// entry with the same filename exists, so re-launches never create duplicates.
/// Note this means a deleted bundled brochure reappears on next launch — the
/// bundled set is treated as the company's standard literature.
enum BundledLiterature {
    struct Item {
        let title: String
        /// Resource filename inside the bundle (and the library entry's filename).
        let filename: String
    }

    /// Library filename of the Fortress brochure — auto-attached to proposals
    /// containing a Fortress line item. The PDF isn't in the bundle yet; drop
    /// `Fortress_Brochure.pdf` into Resources/Literature and it starts seeding
    /// (and auto-attaching) with no further code changes.
    static let fortressFilename = "Fortress_Brochure.pdf"

    static let items: [Item] = [
        Item(title: "Bilco Brochure", filename: "Bilco_Brochure.pdf"),
        Item(title: "Interior Water Pressure Relief System", filename: "Interior Water Pressure Relief System Brochure.pdf"),
        Item(title: "Ram Jack / ECO", filename: "RamJack_ECO_Brochure.pdf"),
        Item(title: "Rockwell Brochure", filename: "Rockwell_Brochure.pdf"),
        Item(title: "Exterior Brochure", filename: "Exterior Brochure – Letter.pdf"),
        Item(title: "Fortress", filename: fortressFilename),
    ]

    /// Inserts any bundled brochure that isn't already in the library.
    @MainActor
    static func seed(into context: ModelContext) {
        let existing: Set<String> = {
            let all = (try? context.fetch(FetchDescriptor<LibraryDocument>())) ?? []
            return Set(all.map(\.filename))
        }()

        var insertedAny = false
        for item in items where !existing.contains(item.filename) {
            let name = (item.filename as NSString).deletingPathExtension
            guard let url = Bundle.main.url(forResource: name, withExtension: "pdf"),
                  let data = try? Data(contentsOf: url) else {
                print("BundledLiterature: missing bundle resource \(item.filename)")
                continue
            }
            context.insert(LibraryDocument(title: item.title, filename: item.filename, pdfData: data))
            insertedAny = true
        }
        if insertedAny {
            try? context.save()
        }
    }
}
