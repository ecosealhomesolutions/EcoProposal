import SwiftUI

#if canImport(PencilKit) && os(iOS)
import PencilKit
#endif

/// Overlays a PKDrawing on top of a photo. Used on the PDF photo page and can be
/// reused anywhere the annotated photo needs to appear (e.g., thumbnails).
struct PhotoInkOverlay: View {
    let annotationData: Data?

    var body: some View {
        #if canImport(PencilKit) && os(iOS)
        if let annotationData,
           let drawing = try? PKDrawing(data: annotationData),
           !drawing.bounds.isEmpty {
            GeometryReader { proxy in
                let image = drawing.image(from: drawing.bounds, scale: 3.0)
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        #endif
    }
}

/// A single US-Letter page rendering one job photo with an optional caption.
struct PhotoPageView: View {
    let photo: PhotoSnapshot
    let pageIndex: Int
    let pageCount: Int
    let snapshot: ProposalSnapshot
    let company: CompanyInfo

    static let pageSize = ProposalDocumentView.pageSize
    private let padding: CGFloat = 36

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                BrandLogo(height: 28)
                Spacer()
                Text("\(snapshot.proposalNumber) • Photo \(pageIndex + 1) of \(pageCount)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if let image = PlatformImage.image(from: photo.imageData) {
                ZStack {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                    PhotoInkOverlay(annotationData: photo.annotationData)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(white: 0.85), lineWidth: 0.5)
                )
            } else {
                Rectangle()
                    .fill(Color(white: 0.95))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(Text("Photo unavailable").foregroundStyle(.secondary))
            }

            if !photo.caption.isEmpty {
                Text(photo.caption)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(padding)
        .frame(width: Self.pageSize.width, height: Self.pageSize.height, alignment: .topLeading)
        .background(Color.white)
        .foregroundStyle(.black)
    }
}
