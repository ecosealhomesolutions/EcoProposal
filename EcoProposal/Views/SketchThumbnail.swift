import SwiftUI

#if canImport(PencilKit) && os(iOS)
import PencilKit
#endif

/// Small preview showing the drawing + annotations over a graph-paper background
/// with compass labels (BACK/RIGHT/FRONT/LEFT).
///
/// The sketch canvas can be far larger than this preview and its content can sit
/// anywhere on it, so we measure the combined bounds of the ink and every
/// annotation, then uniformly scale that whole region to fit — centered — inside
/// the grid. That way the thumbnail always shows the entire sketch rather than a
/// clipped, off-center corner of it.
struct SketchThumbnail: View {
    let sketchData: Data?
    var annotations: [SketchAnnotation] = []
    var segments: [SketchSegment] = []
    var cracks: [SketchCrack] = []

    var body: some View {
        CompassGridFrame(labelFontSize: 10) {
            GeometryReader { geo in
                let bounds = contentBounds
                let scale = fitScale(content: bounds.size, into: geo.size)
                ZStack(alignment: .topLeading) {
                    drawingLayer(origin: bounds.origin)
                    SegmentsLayer(segments: segments, origin: bounds.origin)
                    CracksLayer(cracks: cracks, origin: bounds.origin)
                    ForEach(annotations) { annotation in
                        AnnotationShape(annotation: annotation)
                            .frame(width: annotation.size.width, height: annotation.size.height)
                            .rotationEffect(.degrees(annotation.rotationDegrees))
                            .offset(
                                x: annotation.origin.x - bounds.minX,
                                y: annotation.origin.y - bounds.minY
                            )
                    }
                }
                .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
                .scaleEffect(scale, anchor: .center)
                // Center the (scaled) content within the available grid area.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(white: 0.85), lineWidth: 0.5)
        )
    }

    /// Places the rasterized ink image at its original position within the
    /// combined-content coordinate space (offset so `bounds.origin` maps to 0,0).
    @ViewBuilder
    private func drawingLayer(origin: CGPoint) -> some View {
        #if canImport(PencilKit) && os(iOS)
        if let data = sketchData, let drawing = try? PKDrawing(data: data), !drawing.bounds.isEmpty {
            let inkBounds = drawing.bounds
            // Fixed 3x render keeps the miniature crisp without depending on the
            // (iOS 26-deprecated) UIScreen.main scale.
            let image = drawing.image(from: inkBounds, scale: 3.0)
            Image(uiImage: image)
                .resizable()
                .frame(width: inkBounds.width, height: inkBounds.height)
                .offset(x: inkBounds.minX - origin.x, y: inkBounds.minY - origin.y)
        }
        #endif
    }

    /// The combined bounds of the ink strokes and every annotation, padded so the
    /// content doesn't butt right up against the grid edge. Falls back to a unit
    /// rect when there's nothing to show.
    private var contentBounds: CGRect {
        var rect: CGRect?

        #if canImport(PencilKit) && os(iOS)
        if let data = sketchData, let drawing = try? PKDrawing(data: data), !drawing.bounds.isEmpty {
            rect = drawing.bounds
        }
        #endif

        for annotation in annotations {
            rect = rect.map { $0.union(annotation.frame) } ?? annotation.frame
        }
        for segment in segments {
            rect = rect.map { $0.union(segment.boundingBox) } ?? segment.boundingBox
        }
        for crack in cracks {
            rect = rect.map { $0.union(crack.boundingBox) } ?? crack.boundingBox
        }

        guard let bounds = rect, bounds.width > 0, bounds.height > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        // Pad ~6% of the larger dimension so nothing hugs the border.
        let padding = max(bounds.width, bounds.height) * 0.06
        return bounds.insetBy(dx: -padding, dy: -padding)
    }

    private func fitScale(content: CGSize, into available: CGSize) -> CGFloat {
        guard content.width > 0, content.height > 0,
              available.width > 0, available.height > 0 else { return 1 }
        return min(available.width / content.width, available.height / content.height)
    }
}
