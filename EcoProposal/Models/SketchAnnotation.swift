import Foundation
import CoreGraphics

/// Stamps and text notes overlaid on top of the free-hand drawing.
/// Persisted as a JSON array on `Proposal.sketchAnnotationsData`.
struct SketchAnnotation: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case rectangle
        case circle
        case line
        case arrow
        case text
        case pier         // helical pier / structural steel column
        case sumpPump     // sump pump + crock (architectural convention)
        case egressWindow // basement egress window + window well
        case carbonStrap  // carbon fiber strap bracing a bowing block wall
        case stairs       // basement stairway (plan-view treads + direction arrow)
        case powerBrace   // power brace steel I-beam
    }

    var id: UUID
    var kind: Kind
    var originX: Double
    var originY: Double
    var width: Double
    var height: Double
    var text: String
    /// Rotation in degrees around the annotation's center. Defaults to 0.
    var rotationDegrees: Double
    /// When true, stroke-based shapes (line/arrow) render dashed instead of solid.
    /// Used to mark, e.g., where excavation runs. Defaults to false.
    var isDashed: Bool

    init(
        id: UUID = UUID(),
        kind: Kind,
        origin: CGPoint,
        size: CGSize = CGSize(width: 120, height: 80),
        text: String = "",
        rotationDegrees: Double = 0,
        isDashed: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.originX = Double(origin.x)
        self.originY = Double(origin.y)
        self.width = Double(size.width)
        self.height = Double(size.height)
        self.text = text
        self.rotationDegrees = rotationDegrees
        self.isDashed = isDashed
    }

    // Custom decode so previously saved annotations (before rotation existed) still load.
    private enum CodingKeys: String, CodingKey {
        case id, kind, originX, originY, width, height, text, rotationDegrees, isDashed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.kind = try c.decode(Kind.self, forKey: .kind)
        self.originX = try c.decode(Double.self, forKey: .originX)
        self.originY = try c.decode(Double.self, forKey: .originY)
        self.width = try c.decode(Double.self, forKey: .width)
        self.height = try c.decode(Double.self, forKey: .height)
        self.text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        self.rotationDegrees = try c.decodeIfPresent(Double.self, forKey: .rotationDegrees) ?? 0
        self.isDashed = try c.decodeIfPresent(Bool.self, forKey: .isDashed) ?? false
    }

    var origin: CGPoint {
        get { CGPoint(x: originX, y: originY) }
        set { originX = Double(newValue.x); originY = Double(newValue.y) }
    }

    var size: CGSize {
        get { CGSize(width: width, height: height) }
        set { width = Double(newValue.width); height = Double(newValue.height) }
    }

    var frame: CGRect {
        get { CGRect(origin: origin, size: size) }
        set { origin = newValue.origin; size = newValue.size }
    }
}

/// Convenience encode/decode.
enum SketchAnnotationsCodec {
    static func decode(_ data: Data?) -> [SketchAnnotation] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([SketchAnnotation].self, from: data)) ?? []
    }

    static func encode(_ items: [SketchAnnotation]) -> Data? {
        try? JSONEncoder().encode(items)
    }
}
