import SwiftUI

/// Shared rendering for wall segments and crack lines. The editor, the proposal
/// thumbnail, and the PDF page all draw through these, so what the rep sees on
/// screen is exactly what prints.
enum SketchGeometryStyle {
    static let wallColor = Color(red: 0.13, green: 0.35, blue: 0.55)
    static let wallWidth: CGFloat = 2.5
    static let crackColor = Color(red: 0.55, green: 0.15, blue: 0.12)
    static let crackWidth: CGFloat = 1.6
}

/// Draws a set of wall segments. Positions are absolute canvas coordinates,
/// offset by `origin` (used by thumbnail/PDF to map into content space).
struct SegmentsLayer: View {
    let segments: [SketchSegment]
    var origin: CGPoint = .zero
    var selectedID: UUID? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { p in
                for segment in segments where segment.id != selectedID {
                    p.move(to: offsetPoint(segment.start))
                    p.addLine(to: offsetPoint(segment.end))
                }
            }
            .stroke(
                SketchGeometryStyle.wallColor,
                style: StrokeStyle(lineWidth: SketchGeometryStyle.wallWidth, lineCap: .round)
            )

            if let selectedID, let selected = segments.first(where: { $0.id == selectedID }) {
                Path { p in
                    p.move(to: offsetPoint(selected.start))
                    p.addLine(to: offsetPoint(selected.end))
                }
                .stroke(
                    Color.ecoGreen,
                    style: StrokeStyle(lineWidth: SketchGeometryStyle.wallWidth + 1.5, lineCap: .round)
                )
            }
        }
    }

    private func offsetPoint(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x - origin.x, y: p.y - origin.y)
    }
}

/// Draws crack lines as standardized zigzags along each crack's drag path.
struct CracksLayer: View {
    let cracks: [SketchCrack]
    var origin: CGPoint = .zero

    var body: some View {
        Path { p in
            for crack in cracks {
                CrackShape.addZigzag(to: &p, along: crack.cgPoints, origin: origin)
            }
        }
        .stroke(
            SketchGeometryStyle.crackColor,
            style: StrokeStyle(lineWidth: SketchGeometryStyle.crackWidth, lineCap: .round, lineJoin: .round)
        )
    }
}

/// Zigzag construction for crack rendering. Resamples the drag path at a fixed
/// spacing and offsets alternate samples perpendicular to the path, producing a
/// consistent jagged line no matter how shaky the original drag was. Pure
/// geometry — deterministic, so screen and PDF renders are identical.
enum CrackShape {
    static let sampleSpacing: CGFloat = 10
    static let amplitude: CGFloat = 4

    static func addZigzag(to path: inout Path, along points: [CGPoint], origin: CGPoint = .zero) {
        let spine = resample(points, spacing: sampleSpacing)
        guard spine.count >= 2 else { return }

        var zigzag: [CGPoint] = []
        for (index, point) in spine.enumerated() {
            if index == 0 || index == spine.count - 1 {
                zigzag.append(point) // ends stay on the path
                continue
            }
            // Perpendicular of the local direction, flipping side each sample.
            let previous = spine[index - 1]
            let next = spine[index + 1]
            let dx = next.x - previous.x
            let dy = next.y - previous.y
            let length = max(hypot(dx, dy), 0.001)
            let side: CGFloat = index.isMultiple(of: 2) ? 1 : -1
            zigzag.append(CGPoint(
                x: point.x + (-dy / length) * amplitude * side,
                y: point.y + (dx / length) * amplitude * side
            ))
        }

        path.move(to: CGPoint(x: zigzag[0].x - origin.x, y: zigzag[0].y - origin.y))
        for point in zigzag.dropFirst() {
            path.addLine(to: CGPoint(x: point.x - origin.x, y: point.y - origin.y))
        }
    }

    /// Evenly-spaced samples along a polyline.
    static func resample(_ points: [CGPoint], spacing: CGFloat) -> [CGPoint] {
        guard points.count >= 2 else { return points }
        var result = [points[0]]
        var carried: CGFloat = 0

        for i in 1..<points.count {
            var from = points[i - 1]
            let to = points[i]
            var segmentLength = hypot(to.x - from.x, to.y - from.y)
            while carried + segmentLength >= spacing {
                let remaining = spacing - carried
                let t = remaining / segmentLength
                let sample = CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
                result.append(sample)
                from = sample
                segmentLength -= remaining
                carried = 0
            }
            carried += segmentLength
        }

        if let last = points.last, result.last != last {
            result.append(last)
        }
        return result
    }
}
