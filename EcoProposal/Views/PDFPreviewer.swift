import SwiftUI

#if canImport(PDFKit) && os(iOS)
import PDFKit

/// Displays a generated PDF file with native PDFKit rendering — supports pinch
/// zoom, vertical scroll through multi-page docs, and auto-fits to width.
struct PDFPreviewer: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.usePageViewController(false)
        view.backgroundColor = UIColor(white: 0.9, alpha: 1)
        view.minScaleFactor = 0.25
        view.maxScaleFactor = 4.0
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        // Force a fresh read on each update — file contents may have changed even
        // when the URL is stable (e.g. after a new signature was captured).
        let doc = PDFDocument(url: url)
        if view.document?.dataRepresentation() != doc?.dataRepresentation() {
            view.document = doc
        }
    }
}
/// Same native PDFKit rendering, but for a PDF held in memory (e.g. literature
/// documents stored in SwiftData) rather than a file on disk.
struct PDFDataPreviewer: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.usePageViewController(false)
        view.backgroundColor = UIColor(white: 0.9, alpha: 1)
        view.minScaleFactor = 0.25
        view.maxScaleFactor = 4.0
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.dataRepresentation() != data {
            view.document = PDFDocument(data: data)
        }
    }
}
#else
struct PDFPreviewer: View {
    let url: URL
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text")
            Text("PDF preview requires iPad.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

struct PDFDataPreviewer: View {
    let data: Data
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text")
            Text("PDF preview requires iPad.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
#endif

/// Full-screen sheet wrapping `PDFDataPreviewer` with a title bar and Done button.
/// Used to preview literature documents from the library and the proposal editor.
struct DocumentPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let data: Data

    var body: some View {
        NavigationStack {
            PDFDataPreviewer(data: data)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(title)
                .iosInlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
