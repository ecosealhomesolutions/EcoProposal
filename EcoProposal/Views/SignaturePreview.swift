import SwiftUI

#if canImport(PencilKit) && os(iOS)
import PencilKit
#endif

/// Renders a stored PKDrawing signature blob. Used both in the editor thumbnail
/// and the PDF's signature block. On non-iOS platforms, degrades to a placeholder.
struct SignaturePreview: View {
    let signatureData: Data?

    var body: some View {
        #if canImport(PencilKit) && os(iOS)
        if let data = signatureData,
           let drawing = try? PKDrawing(data: data),
           !drawing.bounds.isEmpty {
            GeometryReader { proxy in
                let image = drawing.image(from: drawing.bounds, scale: UIScreen.main.scale)
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
            }
        } else {
            placeholder
        }
        #else
        placeholder
        #endif
    }

    private var placeholder: some View {
        Text("No signature").font(.caption).foregroundStyle(.secondary)
    }
}
