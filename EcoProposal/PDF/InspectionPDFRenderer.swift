import SwiftUI
import CoreGraphics
import Foundation

@MainActor
enum InspectionPDFRenderer {
    /// Renders an inspection report to a two-page vector PDF in the temp
    /// directory, using the same ImageRenderer + CGContext pattern as
    /// ProposalPDFRenderer so text stays vector/selectable.
    static func renderPDF(for report: InspectionReport, company: CompanyInfo) throws -> URL {
        let snapshot = InspectionSnapshot(from: report)
        let sanitizedNumber = report.reportNumber.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ServiceReport-\(sanitizedNumber).pdf")

        var mediaBox = CGRect(origin: .zero, size: InspectionDocumentView.pageSize)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else {
            throw ProposalPDFRendererError.couldNotCreateContext
        }

        for pageIndex in 0..<2 {
            drawPage(
                in: pdfContext,
                mediaBox: mediaBox,
                content: InspectionDocumentView(
                    snapshot: snapshot,
                    company: company,
                    pageIndex: pageIndex
                )
            )
        }

        // Photo pages — one per site photo, in sort order.
        for (index, photo) in snapshot.photos.enumerated() {
            drawPage(
                in: pdfContext,
                mediaBox: mediaBox,
                content: InspectionPhotoPageView(
                    photo: photo,
                    pageIndex: index,
                    pageCount: snapshot.photos.count,
                    reportNumber: snapshot.reportNumber
                )
            )
        }

        pdfContext.closePDF()
        return url
    }

    private static func drawPage<Content: View>(
        in pdfContext: CGContext,
        mediaBox: CGRect,
        content: Content
    ) {
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(InspectionDocumentView.pageSize)
        renderer.render { size, drawer in
            pdfContext.beginPDFPage(nil)
            let xOffset = max(0, (mediaBox.width - size.width) / 2)
            let yOffset = max(0, (mediaBox.height - size.height) / 2)
            pdfContext.translateBy(x: xOffset, y: yOffset)
            drawer(pdfContext)
            pdfContext.endPDFPage()
        }
    }
}
