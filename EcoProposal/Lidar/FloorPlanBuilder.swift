#if canImport(RoomPlan) && os(iOS)
import Foundation
import CoreGraphics
import PencilKit
import RoomPlan
import UIKit
import simd

/// Converts a RoomPlan `CapturedRoom` into a top-down floor-plan drawing rendered at
/// the sketch grid's 1/4" = 1' scale (18 pt = 1 ft, `GridPaperBackground.oneFoot`).
/// Walls become PencilKit ink strokes; each wall gets a text annotation with its
/// measured length so the sales rep sees real dimensions and can draw on top of the
/// plan in the existing sketch editor.
///
/// This is the bridge that turns a LiDAR measurement into "a drawing the sales guys
/// can draw on" — the output is the same `sketchData` + annotations payload the
/// hand-drawn sketch produces, so the editor, thumbnail, and PDF renderer all reuse it.
enum FloorPlanBuilder {
    /// Points per foot — matches the sketch grid so the plan lands on grid lines.
    private static let pointsPerFoot = GridPaperBackground.oneFoot
    private static let feetPerMeter: CGFloat = 3.28084
    private static var pointsPerMeter: CGFloat { pointsPerFoot * feetPerMeter }
    /// Keeps the plan off the top-left corner of the canvas.
    private static let margin: CGFloat = 48

    static func makeSketch(from room: CapturedRoom) -> GeneratedSketch? {
        let walls = room.walls
        guard !walls.isEmpty else { return nil }

        // Project every wall onto the world XZ (floor) plane, in meters.
        let wallSegments = walls.map { segment(for: $0) }

        // Bounding box across all endpoints so we can normalize into the canvas.
        let xs = wallSegments.flatMap { [$0.a.x, $0.b.x] }
        let zs = wallSegments.flatMap { [$0.a.y, $0.b.y] }
        guard let minX = xs.min(), let maxX = xs.max(),
              let minZ = zs.min(), let maxZ = zs.max() else { return nil }

        // meters -> canvas points. Flip the Z axis so the plan reads like a normal
        // top-down floor plan rather than being vertically mirrored.
        func project(_ p: CGPoint) -> CGPoint {
            CGPoint(
                x: (p.x - minX) * pointsPerMeter + margin,
                y: (maxZ - p.y) * pointsPerMeter + margin
            )
        }

        var strokes: [PKStroke] = []
        var annotations: [SketchAnnotation] = []
        let wallInk = PKInk(.pen, color: .black)

        for (wall, seg) in zip(walls, wallSegments) {
            let a = project(seg.a)
            let b = project(seg.b)
            strokes.append(lineStroke(from: a, to: b, ink: wallInk, width: 3))

            // Dimension label centered on the wall.
            let lengthFeet = CGFloat(wall.dimensions.x) * feetPerMeter
            let size = CGSize(width: 56, height: 20)
            let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            annotations.append(
                SketchAnnotation(
                    kind: .text,
                    origin: CGPoint(x: mid.x - size.width / 2, y: mid.y - size.height / 2),
                    size: size,
                    text: formatFeetInches(lengthFeet)
                )
            )
        }

        // Doors + openings drawn thinner and gray so entries are visible without
        // competing with the wall outline.
        let openingInk = PKInk(.pen, color: .systemGray)
        for opening in room.doors + room.openings {
            let seg = segment(for: opening)
            strokes.append(lineStroke(from: project(seg.a), to: project(seg.b), ink: openingInk, width: 2))
        }

        let drawing = PKDrawing(strokes: strokes)
        return GeneratedSketch(drawingData: drawing.dataRepresentation(), annotations: annotations)
    }

    // MARK: - Geometry

    /// A surface's two endpoints on the world XZ plane (meters). RoomPlan gives each
    /// surface a center `transform` and a bounding-box `dimensions`; the wall runs
    /// along its local X axis, so we walk half its length either side of the center.
    private static func segment(for surface: CapturedRoom.Surface) -> (a: CGPoint, b: CGPoint) {
        let t = surface.transform
        let center = CGPoint(x: CGFloat(t.columns.3.x), y: CGFloat(t.columns.3.z))
        let halfLength = CGFloat(surface.dimensions.x) / 2

        // Local X axis projected onto the floor plane, normalized.
        var dx = CGFloat(t.columns.0.x)
        var dy = CGFloat(t.columns.0.z)
        let magnitude = sqrt(dx * dx + dy * dy)
        if magnitude > 0 { dx /= magnitude; dy /= magnitude }

        return (
            CGPoint(x: center.x - dx * halfLength, y: center.y - dy * halfLength),
            CGPoint(x: center.x + dx * halfLength, y: center.y + dy * halfLength)
        )
    }

    /// A straight PencilKit stroke, sampled at several points so it renders crisply
    /// as a line rather than a two-point spline.
    private static func lineStroke(from a: CGPoint, to b: CGPoint, ink: PKInk, width: CGFloat) -> PKStroke {
        let steps = 12
        let points = (0...steps).map { i -> PKStrokePoint in
            let fraction = CGFloat(i) / CGFloat(steps)
            let location = CGPoint(
                x: a.x + (b.x - a.x) * fraction,
                y: a.y + (b.y - a.y) * fraction
            )
            return PKStrokePoint(
                location: location,
                timeOffset: TimeInterval(i) * 0.01,
                size: CGSize(width: width, height: width),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        let path = PKStrokePath(controlPoints: points, creationDate: Date())
        return PKStroke(ink: ink, path: path)
    }

    /// Formats a length in feet as feet-and-inches, e.g. 12.5 -> `12'-6"`.
    private static func formatFeetInches(_ feet: CGFloat) -> String {
        let totalInches = Int((feet * 12).rounded())
        return "\(totalInches / 12)'-\(totalInches % 12)\""
    }
}
#endif
