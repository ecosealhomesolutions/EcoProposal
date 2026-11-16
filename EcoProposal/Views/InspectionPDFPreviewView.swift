import SwiftUI

/// Renders the inspection report to PDF and shows it full screen with share.
/// Signatures are captured in the editor's Acknowledgement section; the PDF is
/// regenerated on each visit so it always reflects the latest state.
struct InspectionPDFPreviewView: View {
    let report: InspectionReport
    @State private var pdfURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let pdfURL {
                PDFPreviewer(url: pdfURL)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Rendering PDF…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(white: 0.9))
        .navigationTitle("Service Report")
        .iosInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let url = pdfURL {
                    ShareLink(item: url) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                } else {
                    ProgressView()
                }
            }
        }
        .task {
            do {
                pdfURL = try InspectionPDFRenderer.renderPDF(for: report, company: CompanyInfo.load())
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .alert("Couldn't create PDF", isPresented: .constant(errorMessage != nil), presenting: errorMessage) { _ in
            Button("OK") { errorMessage = nil }
        } message: { message in
            Text(message)
        }
    }
}
