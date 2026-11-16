import SwiftUI

#if canImport(PencilKit) && os(iOS)
import PencilKit
#endif

/// A full US-Letter page showing the job sketch over graph paper with compass labels.
/// Rendered as a page of the proposal PDF when a sketch or annotations exist.
///
/// Everything — freehand ink, stamps, walls — is laid out in one shared canvas
/// coordinate space and scaled uniformly to fit the page. This keeps strokes
/// faithful to what the rep drew: no cropping the ink to its own bounds and no
/// independent aspect-fitting that distorts squiggles or shifts them relative to
/// the stamped annotations.
struct SketchPageView: View {
    let snapshot: ProposalSnapshot
    let company: CompanyInfo

    static let pageSize = ProposalDocumentView.pageSize
    private let padding: CGFloat = 36

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                BrandLogo(height: 28)
                Spacer()
                Text("\(snapshot.proposalNumber) • Job Sketch")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            CompassGridFrame(labelFontSize: 12) {
                GeometryReader { geo in
                    let bounds = contentBounds
                    let scale = fitScale(content: bounds.size, into: geo.size)
                    ZStack(alignment: .topLeading) {
                        drawingLayer(origin: bounds.origin)
                        SegmentsLayer(segments: snapshot.sketchSegments, origin: bounds.origin)
                        CracksLayer(cracks: snapshot.sketchCracks, origin: bounds.origin)
                        ForEach(snapshot.sketchAnnotations) { annotation in
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(white: 0.75), lineWidth: 0.5)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(padding)
        .frame(width: Self.pageSize.width, height: Self.pageSize.height, alignment: .topLeading)
        .background(Color.white)
        .foregroundStyle(.black)
    }

    /// Ink rendered at its native size and position within the shared content space —
    /// scaling happens once, uniformly, for the whole sheet.
    @ViewBuilder
    private func drawingLayer(origin: CGPoint) -> some View {
        #if canImport(PencilKit) && os(iOS)
        if let data = snapshot.sketchData,
           let drawing = try? PKDrawing(data: data),
           !drawing.bounds.isEmpty {
            let inkBounds = drawing.bounds
            let image = drawing.image(from: inkBounds, scale: 3.0)
            Image(uiImage: image)
                .resizable()
                .frame(width: inkBounds.width, height: inkBounds.height)
                .offset(x: inkBounds.minX - origin.x, y: inkBounds.minY - origin.y)
        }
        #endif
    }

    /// Combined bounds of ink + annotations, padded slightly. Falls back to a unit
    /// rect when the sketch is empty.
    private var contentBounds: CGRect {
        var rect: CGRect?

        #if canImport(PencilKit) && os(iOS)
        if let data = snapshot.sketchData,
           let drawing = try? PKDrawing(data: data),
           !drawing.bounds.isEmpty {
            rect = drawing.bounds
        }
        #endif

        for annotation in snapshot.sketchAnnotations {
            rect = rect.map { $0.union(annotation.frame) } ?? annotation.frame
        }
        for segment in snapshot.sketchSegments {
            rect = rect.map { $0.union(segment.boundingBox) } ?? segment.boundingBox
        }
        for crack in snapshot.sketchCracks {
            rect = rect.map { $0.union(crack.boundingBox) } ?? crack.boundingBox
        }

        guard let bounds = rect, bounds.width > 0, bounds.height > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        let pad = max(bounds.width, bounds.height) * 0.04
        return bounds.insetBy(dx: -pad, dy: -pad)
    }

    private func fitScale(content: CGSize, into available: CGSize) -> CGFloat {
        guard content.width > 0, content.height > 0,
              available.width > 0, available.height > 0 else { return 1 }
        return min(available.width / content.width, available.height / content.height)
    }
}
