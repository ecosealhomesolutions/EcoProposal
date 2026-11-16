import Foundation
import CoreGraphics

/// A straight wall segment drawn with the Walls tool. Segments snap end-to-end so
/// reps can outline any foundation shape (bays, octagons, partial walls).
/// Persisted as a JSON array on `Proposal.sketchSegmentsData`.
struct SketchSegment: Codable, Identifiable, Equatable {
    var id: UUID
    var x1: Double
    var y1: Double
    var x2: Double
    var y2: Double

    init(id: UUID = UUID(), start: CGPoint, end: CGPoint) {
        self.id = id
        self.x1 = Double(start.x)
        self.y1 = Double(start.y)
        self.x2 = Double(end.x)
        self.y2 = Double(end.y)
    }

    var start: CGPoint {
        get { CGPoint(x: x1, y: y1) }
        set { x1 = Double(newValue.x); y1 = Double(newValue.y) }
    }

    var end: CGPoint {
        get { CGPoint(x: x2, y: y2) }
        set { x2 = Double(newValue.x); y2 = Double(newValue.y) }
    }

    var length: CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }

    /// Point at parameter t ∈ [0, 1] along the segment.
    func point(at t: CGFloat) -> CGPoint {
        CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
    }

    /// Distance from a point to this segment, and the parameter of the closest spot.
    func closest(to p: CGPoint) -> (distance: CGFloat, t: CGFloat) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return (hypot(p.x - start.x, p.y - start.y), 0) }
        let t = max(0, min(1, ((p.x - start.x) * dx + (p.y - start.y) * dy) / lengthSquared))
        let proj = point(at: t)
        return (hypot(p.x - proj.x, p.y - proj.y), t)
    }

    var boundingBox: CGRect {
        CGRect(x: min(x1, x2), y: min(y1, y2), width: abs(x2 - x1), height: abs(y2 - y1))
            .insetBy(dx: -2, dy: -2)
    }
}

/// A foundation crack drawn with the Crack tool. The rep drags a path; rendering
/// standardizes it into a consistent zigzag (see `CrackShape`), so cracks look
/// clean and identical on screen and in the PDF.
/// Persisted as a JSON array on `Proposal.sketchCracksData`.
struct SketchCrack: Codable, Identifiable, Equatable {
    var id: UUID
    var points: [CGPointCodable]

    init(id: UUID = UUID(), points: [CGPoint]) {
        self.id = id
        self.points = points.map(CGPointCodable.init)
    }

    var cgPoints: [CGPoint] { points.map(\.cg) }

    var boundingBox: CGRect {
        guard let first = points.first else { return .zero }
        var rect = CGRect(origin: first.cg, size: .zero)
        for p in points.dropFirst() {
            rect = rect.union(CGRect(origin: p.cg, size: .zero))
        }
        return rect.insetBy(dx: -6, dy: -6)
    }
}

/// Partial-erase geometry. The eraser is a stroked path with a radius; anything
/// a wall segment or crack has inside that stroke is removed, and what remains
/// is split into independent pieces.
enum SketchEraser {
    static let radius: CGFloat = 12
    /// Pieces shorter than this after erasing are dropped as noise.
    static let minPieceLength: CGFloat = 6

    // MARK: Segments

    static func erase(segments: [SketchSegment], along path: [CGPoint]) -> [SketchSegment] {
        segments.flatMap { erase(segment: $0, along: path) }
    }

    /// Returns the pieces of `segment` that survive the eraser path: collect the
    /// parameter interval each eraser sample wipes out, merge them, and keep the
    /// complement as new segments.
    private static func erase(segment: SketchSegment, along path: [CGPoint]) -> [SketchSegment] {
        let length = segment.length
        guard length > 0 else { return [] }

        var wiped: [(Double, Double)] = []
        for point in path {
            let (distance, t) = segment.closest(to: point)
            guard distance <= radius else { continue }
            // Half-width of the wiped span along the segment, from the chord of
            // the eraser circle at this distance.
            let chordHalf = sqrt(max(0, radius * radius - distance * distance))
            let halfSpan = Double(max(chordHalf, 2) / length)
            wiped.append((Double(t) - halfSpan, Double(t) + halfSpan))
        }
        guard !wiped.isEmpty else { return [segment] }

        // Merge overlapping wiped intervals.
        wiped.sort { $0.0 < $1.0 }
        var merged: [(Double, Double)] = []
        for interval in wiped {
            if var last = merged.last, interval.0 <= last.1 {
                last.1 = max(last.1, interval.1)
                merged[merged.count - 1] = last
            } else {
                merged.append(interval)
            }
        }

        // Complement of the wiped intervals within [0, 1] → surviving pieces.
        var pieces: [SketchSegment] = []
        var cursor = 0.0
        for (from, to) in merged {
            if from > cursor {
                appendPiece(of: segment, from: cursor, to: from, into: &pieces)
            }
            cursor = max(cursor, to)
        }
        if cursor < 1 {
            appendPiece(of: segment, from: cursor, to: 1, into: &pieces)
        }
        return pieces
    }

    private static func appendPiece(
        of segment: SketchSegment, from: Double, to: Double, into pieces: inout [SketchSegment]
    ) {
        let start = segment.point(at: CGFloat(max(0, from)))
        let end = segment.point(at: CGFloat(min(1, to)))
        guard hypot(end.x - start.x, end.y - start.y) >= minPieceLength else { return }
        pieces.append(SketchSegment(start: start, end: end))
    }

    // MARK: Cracks

    static func erase(cracks: [SketchCrack], along path: [CGPoint]) -> [SketchCrack] {
        cracks.flatMap { erase(crack: $0, along: path) }
    }

    private static func erase(crack: SketchCrack, along path: [CGPoint]) -> [SketchCrack] {
        let points = crack.cgPoints
        var runs: [[CGPoint]] = []
        var current: [CGPoint] = []

        for point in points {
            let wiped = path.contains { hypot($0.x - point.x, $0.y - point.y) <= radius }
            if wiped {
                if current.count >= 2 { runs.append(current) }
                current = []
            } else {
                current.append(point)
            }
        }
        if current.count >= 2 { runs.append(current) }

        if runs.count == 1 && runs[0].count == points.count {
            return [crack] // untouched — keep identity stable
        }
        return runs.map { SketchCrack(points: $0) }
    }

    // MARK: Rectangle conversion

    /// The rectangle annotation's four sides as wall segments, honoring rotation.
    static func rectangleSides(of annotation: SketchAnnotation) -> [SketchSegment] {
        let frame = annotation.frame
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let radians = annotation.rotationDegrees * .pi / 180

        func rotated(_ p: CGPoint) -> CGPoint {
            let dx = p.x - center.x
            let dy = p.y - center.y
            return CGPoint(
                x: center.x + dx * cos(radians) - dy * sin(radians),
                y: center.y + dx * sin(radians) + dy * cos(radians)
            )
        }

        let corners = [
            CGPoint(x: frame.minX, y: frame.minY),
            CGPoint(x: frame.maxX, y: frame.minY),
            CGPoint(x: frame.maxX, y: frame.maxY),
            CGPoint(x: frame.minX, y: frame.maxY),
        ].map(rotated)

        return (0..<4).map { SketchSegment(start: corners[$0], end: corners[($0 + 1) % 4]) }
    }

    /// True when any eraser sample lands on the rectangle's border (within radius).
    static func pathTouchesRectangle(_ path: [CGPoint], rectangle annotation: SketchAnnotation) -> Bool {
        let sides = rectangleSides(of: annotation)
        return path.contains { point in
            sides.contains { $0.closest(to: point).distance <= radius }
        }
    }
}

enum SketchGeometryCodec {
    static func decodeSegments(_ data: Data?) -> [SketchSegment] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([SketchSegment].self, from: data)) ?? []
    }

    static func encodeSegments(_ items: [SketchSegment]) -> Data? {
        items.isEmpty ? nil : try? JSONEncoder().encode(items)
    }

    static func decodeCracks(_ data: Data?) -> [SketchCrack] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([SketchCrack].self, from: data)) ?? []
    }

    static func encodeCracks(_ items: [SketchCrack]) -> Data? {
        items.isEmpty ? nil : try? JSONEncoder().encode(items)
    }
}
