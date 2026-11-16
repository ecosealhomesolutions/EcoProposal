import SwiftUI
import CoreGraphics
import Foundation

#if canImport(UIKit)
import UIKit
#endif

enum ProposalPDFRendererError: Error {
    case couldNotCreateContext
}

@MainActor
enum ProposalPDFRenderer {
    /// Renders a proposal to a multi-page vector PDF in the temp directory.
    ///
    /// Page composition:
    ///   1. Main proposal (customer, line items, totals, terms)
    ///   2. Notes, if any (own page so long notes never clip)
    ///   3. Job sketch, if present
    ///   4..N. One page per photo, in sort order, then attached literature
    ///
    /// Uses the Apple-documented ImageRenderer + CGContext PDF pattern so text stays
    /// vector/selectable.
    static func renderPDF(for proposal: Proposal, company: CompanyInfo) throws -> URL {
        let snapshot = ProposalSnapshot(from: proposal)
        let sanitizedNumber = proposal.proposalNumber.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Proposal-\(sanitizedNumber).pdf")
        try render(snapshot: snapshot, company: company, to: url)
        return url
    }

    /// Target ceiling for uploaded/emailed proposals.
    static let uploadTargetBytes = 10 * 1024 * 1024

    /// Photo downsampling steps tried in order until the output is under target.
    /// ~1400px long edge ≈ 150 DPI on a letter-width photo block.
    private static let compressionSteps: [(maxDimension: CGFloat, quality: CGFloat)] = [
        (1400, 0.6), (1100, 0.45), (900, 0.3),
    ]

    /// Renders a compressed variant for upload/email: photos are downsampled and
    /// JPEG-recompressed (text, sketch, and line work stay vector-sharp). Steps
    /// image quality down until the file fits `targetBytes` or the steps run out.
    /// Returns the URL and the final byte count. The full-quality PDF from
    /// `renderPDF` is untouched.
    static func renderCompressedPDF(
        for proposal: Proposal,
        company: CompanyInfo,
        targetBytes: Int = uploadTargetBytes
    ) throws -> (url: URL, bytes: Int) {
        let snapshot = ProposalSnapshot(from: proposal)
        let sanitizedNumber = proposal.proposalNumber.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Proposal-\(sanitizedNumber)-upload.pdf")

        var bytes = 0
        for step in compressionSteps {
            var compressed = snapshot
            compressed.photos = snapshot.photos.map { photo in
                var copy = photo
                copy.imageData = downsampled(
                    photo.imageData, maxDimension: step.maxDimension, quality: step.quality
                )
                return copy
            }
            try render(snapshot: compressed, company: company, to: url)
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            bytes = (attributes?[.size] as? Int) ?? 0
            if bytes > 0 && bytes <= targetBytes {
                return (url, bytes)
            }
        }
        // Even the smallest step didn't fit (e.g. heavy attached literature) —
        // return the best effort; the caller shows the real size either way.
        return (url, bytes)
    }

    /// Scales an image down so its long edge is at most `maxDimension` and
    /// re-encodes as JPEG. Returns the original data when it can't be decoded
    /// (or on non-UIKit platforms).
    private static func downsampled(_ data: Data, maxDimension: CGFloat, quality: CGFloat) -> Data {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return data }
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let longEdge = max(pixelWidth, pixelHeight)
        let ratio = min(1, maxDimension / max(longEdge, 1))

        let targetSize = CGSize(width: pixelWidth * ratio, height: pixelHeight * ratio)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let scaled = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        if let jpeg = scaled.jpegData(compressionQuality: quality), jpeg.count < data.count {
            return jpeg
        }
        return data
        #else
        return data
        #endif
    }

    private static func render(snapshot: ProposalSnapshot, company: CompanyInfo, to url: URL) throws {
        var mediaBox = CGRect(origin: .zero, size: ProposalDocumentView.pageSize)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else {
            throw ProposalPDFRendererError.couldNotCreateContext
        }

        // Contract pages — line items flow across pages when needed; the totals,
        // terms, and signature block always travel together on the final page.
        let contract = contractPages(for: snapshot)
        for (index, pageItems) in contract.pages.enumerated() {
            let isLast = index == contract.pages.count - 1
            drawPage(
                in: pdfContext,
                mediaBox: mediaBox,
                content: ProposalDocumentView(
                    snapshot: snapshot,
                    company: company,
                    pageItems: pageItems,
                    lineItemFontSize: contract.fontSize,
                    isFirstPage: index == 0,
                    isClosingPage: isLast,
                    continuationNote: isLast ? nil : "Line items continue on the next page…"
                ),
                proposedSize: ProposalDocumentView.pageSize
            )
        }

        // Notes pages — scope-of-work notes get full pages of their own so they
        // never collide with a long line-item table on page 1. Long notes flow
        // across as many pages as needed.
        let noteChunks = NotesPaginator.pageChunks(
            rtf: snapshot.scopeOfWorkRTF,
            plain: snapshot.scopeOfWork,
            contentSize: NotesPageView.contentSize
        )
        for (index, chunk) in noteChunks.enumerated() {
            drawPage(
                in: pdfContext,
                mediaBox: mediaBox,
                content: NotesPageView(
                    snapshot: snapshot,
                    company: company,
                    content: chunk,
                    pageIndex: index,
                    pageCount: noteChunks.count
                ),
                proposedSize: NotesPageView.pageSize
            )
        }

        // Sketch page (if any ink, annotations, walls, or cracks)
        if snapshot.sketchData != nil || !snapshot.sketchAnnotations.isEmpty
            || !snapshot.sketchSegments.isEmpty || !snapshot.sketchCracks.isEmpty {
            drawPage(
                in: pdfContext,
                mediaBox: mediaBox,
                content: SketchPageView(snapshot: snapshot, company: company),
                proposedSize: SketchPageView.pageSize
            )
        }

        // Photo pages
        for (index, photo) in snapshot.photos.enumerated() {
            drawPage(
                in: pdfContext,
                mediaBox: mediaBox,
                content: PhotoPageView(
                    photo: photo,
                    pageIndex: index,
                    pageCount: snapshot.photos.count,
                    snapshot: snapshot,
                    company: company
                ),
                proposedSize: PhotoPageView.pageSize
            )
        }

        // Attached literature — append every page of each attached PDF, preserving
        // each page's native size so brochures print at their intended layout.
        for docData in snapshot.documentPDFs {
            appendPDFPages(from: docData, into: pdfContext)
        }

        pdfContext.closePDF()
    }

    // MARK: - Contract page layout

    /// Splits the line items across contract pages so the totals + terms +
    /// signature block always fit, as one unit, on the final page.
    ///
    /// Strategy (per spec): first shrink the line-item font progressively down to
    /// 8 pt; if the single page still can't hold everything, flow the overflow
    /// onto continuation pages. Heights are conservative estimates — being a
    /// little under just leaves whitespace, never a clipped signature.
    static func contractPages(for snapshot: ProposalSnapshot) -> (fontSize: CGFloat, pages: [[LineItemSnapshot]]) {
        let items = snapshot.showLineItemsOnPDF ? snapshot.lineItems : []
        let pageHeight = ProposalDocumentView.pageSize.height - 72   // margins
        let headerHeight: CGFloat = 95                                // logo row + divider + spacing

        // First-page fixed blocks: parties + lead source + contract scope checklist.
        var firstPageFixed: CGFloat = headerHeight + 100
        if !snapshot.inspector.isEmpty || !snapshot.referral.isEmpty
            || (snapshot.permitRequired && snapshot.showPermitOnPDF) {
            firstPageFixed += 45
        }
        let scopeLines = max(exteriorScopeLineCount(snapshot), interiorScopeLineCount(snapshot), serviceScopeLineCount(snapshot))
        if scopeLines > 0 {
            firstPageFixed += 40 + CGFloat(scopeLines) * 15
        }

        // Closing block: totals + notes pointer + terms + signature + spacing.
        var closingReserve: CGFloat = 140 + 110 + 30
        if !snapshot.terms.isEmpty {
            closingReserve += 22 + CGFloat(max(1, snapshot.terms.count / 110)) * 13
        }
        if !snapshot.scopeOfWork.isEmpty { closingReserve += 14 }

        guard !items.isEmpty else { return (10, [[]]) }

        // Step 1 — progressive font scaling.
        let fontSize: CGFloat = items.count <= 12 ? 10 : (items.count <= 20 ? 9 : 8)

        func rowHeight(_ item: LineItemSnapshot, size: CGFloat) -> CGFloat {
            // Description column is ~350 pt wide → roughly 60 chars/line at 10 pt,
            // proportionally more at smaller sizes. +1 line of slack is built into
            // the ceiling division; 10 pt covers the row's vertical padding.
            let charsPerLine = Int(60 * 10 / size)
            let lines = max(1, Int(ceil(Double(item.description.count) / Double(charsPerLine))))
            return CGFloat(lines) * (size + 4) + 10
        }

        let tableHeader: CGFloat = fontSize + 14
        let totalRows = items.reduce(CGFloat.zero) { $0 + rowHeight($1, size: fontSize) }

        // Everything fits on one page at the scaled size? Done.
        if firstPageFixed + tableHeader + totalRows + closingReserve <= pageHeight {
            return (fontSize, [items])
        }

        // Step 2 — flow across pages. First page has the header blocks; the
        // final page must hold the closing block, with items above it only if
        // they fit.
        var pages: [[LineItemSnapshot]] = []
        var current: [LineItemSnapshot] = []
        var used: CGFloat = firstPageFixed + tableHeader
        var budget = pageHeight - 20 // continuation-note allowance

        for item in items {
            let height = rowHeight(item, size: fontSize)
            if used + height > budget {
                pages.append(current)
                current = []
                used = headerHeight + tableHeader
                budget = pageHeight - 20
            }
            current.append(item)
            used += height
        }

        // Can the last chunk share its page with the closing block?
        if used + closingReserve <= pageHeight {
            pages.append(current)
        } else {
            pages.append(current)
            pages.append([]) // closing block gets a page of its own
        }
        return (fontSize, pages)
    }

    private static func exteriorScopeLineCount(_ s: ProposalSnapshot) -> Int {
        [!s.extLinealFeet.isEmpty, s.extWallsWaterproof, s.extDownspoutDrains,
         s.extBelowGradeDrainage, s.extACRemoval, s.extGravelBackfill, s.extRoughGrade]
            .filter { $0 }.count
    }

    private static func interiorScopeLineCount(_ s: ProposalSnapshot) -> Int {
        [s.intWaterPressureRelief, s.intSumpPump, s.intCarbonFiber, s.intPowerBrace, s.intHelicalPiers]
            .filter { $0 }.count
    }

    private static func serviceScopeLineCount(_ s: ProposalSnapshot) -> Int {
        [s.svcSumpPump, s.svcBatteryBackup, s.svcAnnualMaintenance, s.svcDrainCleaning,
         s.svcCrackRepair, s.svcDehumidifier, s.svcWarrantyVisit, !s.svcOtherWork.isEmpty]
            .filter { $0 }.count
    }

    /// Draws every page of a source PDF (given as raw bytes) into the output context,
    /// one output page per source page, matching each source page's media box.
    private static func appendPDFPages(from data: Data, into pdfContext: CGContext) {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider),
              document.numberOfPages > 0 else { return }

        for pageNumber in 1...document.numberOfPages {
            guard let page = document.page(at: pageNumber) else { continue }
            var mediaBox = page.getBoxRect(.mediaBox)
            let pageInfo = [
                kCGPDFContextMediaBox as String: Data(bytes: &mediaBox, count: MemoryLayout<CGRect>.size)
            ] as CFDictionary
            pdfContext.beginPDFPage(pageInfo)
            pdfContext.drawPDFPage(page)
            pdfContext.endPDFPage()
        }
    }

    private static func drawPage<Content: View>(
        in pdfContext: CGContext,
        mediaBox: CGRect,
        content: Content,
        proposedSize: CGSize
    ) {
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(proposedSize)

        renderer.render { size, drawer in
            pdfContext.beginPDFPage(nil)
            // Center on the page (no Y-flip: ImageRenderer already draws in PDF orientation).
            let xOffset = max(0, (mediaBox.width - size.width) / 2)
            let yOffset = max(0, (mediaBox.height - size.height) / 2)
            pdfContext.translateBy(x: xOffset, y: yOffset)
            drawer(pdfContext)
            pdfContext.endPDFPage()
        }
    }
}
