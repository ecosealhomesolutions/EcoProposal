import Foundation
import SwiftData

/// A plan set uploaded by a sales rep on a New Construction proposal. Holds one or
/// more `BlueprintPage`s — a multi-page PDF becomes a single plan set with all its
/// pages beneath it, sharing one calibration (architects almost always draw the
/// whole set at the same architectural scale).
@Model
final class Blueprint {
    var id: UUID
    var caption: String
    var sortOrder: Int
    var createdAt: Date
    var proposal: Proposal?

    /// Once calibrated, how many image pixels equal 1 real-world foot. Shared
    /// across every page in this plan set.
    var pixelsPerFoot: Double?

    /// Raw scale annotation text extracted from the PDF (e.g. `1/4" = 1'-0"`).
    var detectedPDFScale: String?

    /// Rasterization scale (image pixels per PDF point) used when we rendered
    /// the source PDF into images.
    var pdfRasterizationScale: Double?

    @Relationship(deleteRule: .cascade, inverse: \BlueprintPage.blueprint)
    var pages: [BlueprintPage] = []

    var remoteRecordID: Int?
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        caption: String = "",
        sortOrder: Int = 0,
        pixelsPerFoot: Double? = nil,
        detectedPDFScale: String? = nil,
        pdfRasterizationScale: Double? = nil,
        proposal: Proposal? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.caption = caption
        self.sortOrder = sortOrder
        self.pixelsPerFoot = pixelsPerFoot
        self.detectedPDFScale = detectedPDFScale
        self.pdfRasterizationScale = pdfRasterizationScale
        self.proposal = proposal
        self.createdAt = createdAt
        self.updatedAt = Date()
    }

    var isCalibrated: Bool {
        (pixelsPerFoot ?? 0) > 0
    }

    var sortedPages: [BlueprintPage] {
        pages.sorted { $0.sortOrder < $1.sortOrder }
    }
}

/// A single page inside a plan set. Owns its rasterized image and the measurements
/// the rep drew on it; inherits calibration from the parent plan set.
@Model
final class BlueprintPage {
    var id: UUID
    var sortOrder: Int
    var blueprint: Blueprint?

    @Attribute(.externalStorage) var imageData: Data

    /// JSON-encoded `[Measurement]` — lines / rectangles / polygons / calibration ref.
    var measurementsData: Data?

    var updatedAt: Date

    init(
        id: UUID = UUID(),
        imageData: Data,
        sortOrder: Int = 0,
        blueprint: Blueprint? = nil
    ) {
        self.id = id
        self.imageData = imageData
        self.sortOrder = sortOrder
        self.blueprint = blueprint
        self.updatedAt = Date()
    }

    var measurements: [Measurement] {
        get { MeasurementsCodec.decode(measurementsData) }
        set { measurementsData = MeasurementsCodec.encode(newValue) }
    }
}

/// One measurement layered on a blueprint page.
struct Measurement: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case line
        case rectangle
        case polygon
        case calibration
    }

    var id: UUID
    var kind: Kind
    var points: [CGPointCodable]
    var label: String
    /// If this measurement auto-created a LineItem on the proposal (area
    /// measurements only), we record its UUID so Undo can remove both together.
    var lineItemID: UUID?

    init(
        id: UUID = UUID(),
        kind: Kind,
        points: [CGPoint],
        label: String = "",
        lineItemID: UUID? = nil
    ) {
        self.id = id
        self.kind = kind
        self.points = points.map(CGPointCodable.init)
        self.label = label
        self.lineItemID = lineItemID
    }

    // Custom decode so measurements saved before `lineItemID` existed still load.
    private enum CodingKeys: String, CodingKey {
        case id, kind, points, label, lineItemID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.kind = try c.decode(Kind.self, forKey: .kind)
        self.points = try c.decode([CGPointCodable].self, forKey: .points)
        self.label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        self.lineItemID = try c.decodeIfPresent(UUID.self, forKey: .lineItemID)
    }
}

struct CGPointCodable: Codable, Equatable {
    var x: Double
    var y: Double

    init(_ point: CGPoint) {
        self.x = Double(point.x)
        self.y = Double(point.y)
    }

    var cg: CGPoint { CGPoint(x: x, y: y) }
}

enum MeasurementsCodec {
    static func decode(_ data: Data?) -> [Measurement] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([Measurement].self, from: data)) ?? []
    }

    static func encode(_ items: [Measurement]) -> Data? {
        try? JSONEncoder().encode(items)
    }
}
