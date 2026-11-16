import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if canImport(PDFKit) && os(iOS)
import PDFKit
#endif

/// Editor section shown for New Construction proposals. Reps upload plan-set
/// PDFs (or images) — each import becomes ONE Blueprint plan set with all its
/// pages inside, sharing one calibration. Tapping opens the paged takeoff editor.
struct TakeoffSection: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var proposal: Proposal
    @State private var isImporting = false
    @State private var loadError: String?
    @State private var isProcessing = false

    private let thumbSize: CGFloat = 130
    private let columns = [GridItem(.adaptive(minimum: 130), spacing: 12)]

    private var sortedBlueprints: [Blueprint] {
        proposal.blueprints.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Aggregate rectangle + closed-polygon area across every calibrated plan set.
    private var totalMeasuredSquareFeet: Double {
        sortedBlueprints.reduce(0) { total, bp in
            guard let pxPerFt = bp.pixelsPerFoot, pxPerFt > 0 else { return total }
            let pageArea = bp.pages.reduce(0.0) { pageTotal, page in
                pageTotal + areaSqFt(measurements: page.measurements, pxPerFt: pxPerFt)
            }
            return total + pageArea
        }
    }

    var body: some View {
        Section {
            if sortedBlueprints.isEmpty {
                Text("No plan sets yet. Upload the architect's PDF to start marking up.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(sortedBlueprints) { bp in
                        NavigationLink(value: bp) {
                            BlueprintThumbnail(
                                blueprint: bp,
                                size: thumbSize,
                                onDelete: { delete(bp) }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)

                if totalMeasuredSquareFeet > 0 {
                    HStack {
                        Text("Total measured area (all plan sets)")
                            .font(.subheadline)
                        Spacer()
                        Text("\(totalMeasuredSquareFeet, specifier: "%.1f") sq ft")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.ecoNavy)
                    }
                }
            }

            Button {
                isImporting = true
            } label: {
                HStack {
                    if isProcessing {
                        ProgressView()
                        Text("Processing plan set…")
                    } else {
                        Label("Upload plan set (PDF)", systemImage: "doc.badge.plus")
                    }
                }
            }
            .buttonStyle(.bordered)
            .disabled(isProcessing)
        } header: {
            Text("Takeoff — Blueprints")
        } footer: {
            if let loadError {
                Text(loadError).foregroundStyle(.red)
            } else {
                Text("Upload the architect's PDF. All pages come in as one plan set that shares a single calibration — set the scale once and every page uses it.")
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.pdf, .image],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task { await importFiles(urls: urls) }
            case .failure(let error):
                loadError = "Couldn't open plan set: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Import

    @MainActor
    private func importFiles(urls: [URL]) async {
        loadError = nil
        isProcessing = true
        defer { isProcessing = false }

        for url in urls {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

            guard let data = try? Data(contentsOf: url) else {
                loadError = "Couldn't read \(url.lastPathComponent)."
                continue
            }

            if url.pathExtension.lowercased() == "pdf" {
                addPDF(data: data, name: url.deletingPathExtension().lastPathComponent)
            } else {
                addSingleImage(data: data, caption: url.deletingPathExtension().lastPathComponent)
            }
        }
    }

    /// PDF → one Blueprint with N BlueprintPages, sharing calibration.
    private func addPDF(data: Data, name: String) {
        #if canImport(PDFKit) && os(iOS)
        guard let doc = PDFDocument(data: data) else {
            loadError = "Couldn't decode PDF \(name)."
            return
        }

        // Detect scale from any page's text (usually the cover / first sheet has it).
        let detectedScale: String? = {
            for i in 0..<doc.pageCount {
                if let text = doc.page(at: i)?.string,
                   let match = extractScaleAnnotation(from: text) {
                    return match
                }
            }
            return nil
        }()

        // Target ~3000 pixel width for detail — with format.scale=1, this maps
        // directly to actual PNG pixels (no hidden device-scale multiplier).
        let firstBounds = doc.page(at: 0)?.bounds(for: .mediaBox) ?? .zero
        let rasterScale = min(3.0, 3000.0 / max(firstBounds.width, 1))

        // Force scale=1 so image pixels == target size. Without this, the
        // renderer silently doubles/triples on retina and every ratio-based
        // scale (typed or auto-detected) comes out multiplied by device scale
        // — making measurements read 2×–3× too large per axis (4×–9× area).
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true

        // We'll measure the actual pixel-to-point ratio from the first rendered
        // page so the stored rasterization scale is empirically correct.
        var measuredRasterScale: Double?

        let blueprint = Blueprint(
            caption: name,
            sortOrder: (proposal.blueprints.map(\.sortOrder).max() ?? -1) + 1,
            detectedPDFScale: detectedScale,
            pdfRasterizationScale: Double(rasterScale),   // provisional; replaced below
            proposal: proposal
        )
        modelContext.insert(blueprint)

        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let target = CGSize(width: bounds.width * rasterScale, height: bounds.height * rasterScale)
            let renderer = UIGraphicsImageRenderer(size: target, format: format)
            let img = renderer.image { ctx in
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: target))
                ctx.cgContext.saveGState()
                ctx.cgContext.translateBy(x: 0, y: target.height)
                ctx.cgContext.scaleBy(x: rasterScale, y: -rasterScale)
                page.draw(with: .mediaBox, to: ctx.cgContext)
                ctx.cgContext.restoreGState()
            }
            if let png = img.pngData() {
                let bpPage = BlueprintPage(imageData: png, sortOrder: i, blueprint: blueprint)
                modelContext.insert(bpPage)
                blueprint.pages.append(bpPage)

                // On the FIRST page, measure the actual PNG-loaded ratio and
                // record it as the definitive scale. Handles any edge cases in
                // renderer behavior (page rotation, userUnit, etc.).
                if measuredRasterScale == nil,
                   let loaded = UIImage(data: png),
                   bounds.width > 0 {
                    measuredRasterScale = Double(loaded.size.width) / Double(bounds.width)
                }
            }
        }

        if let m = measuredRasterScale {
            blueprint.pdfRasterizationScale = m
        }

        proposal.blueprints.append(blueprint)
        try? modelContext.save()
        #else
        loadError = "PDF import requires iPad."
        #endif
    }

    /// Single image upload → one Blueprint with one page (no PDF scale detection).
    private func addSingleImage(data: Data, caption: String) {
        let blueprint = Blueprint(
            caption: caption,
            sortOrder: (proposal.blueprints.map(\.sortOrder).max() ?? -1) + 1,
            proposal: proposal
        )
        modelContext.insert(blueprint)
        let page = BlueprintPage(imageData: data, sortOrder: 0, blueprint: blueprint)
        modelContext.insert(page)
        blueprint.pages.append(page)
        proposal.blueprints.append(blueprint)
        try? modelContext.save()
    }

    private func extractScaleAnnotation(from text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        let pattern = #"([0-9]+)(?:/([0-9]+))?"?\s*=\s*([0-9]+)\s*'"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let r = Range(match.range, in: text) else { return nil }
        return String(text[r])
    }

    private func delete(_ bp: Blueprint) {
        modelContext.delete(bp)
        try? modelContext.save()
    }

    private func areaSqFt(measurements: [Measurement], pxPerFt: Double) -> Double {
        guard pxPerFt > 0 else { return 0 }
        var total = 0.0
        for m in measurements {
            switch m.kind {
            case .rectangle where m.points.count >= 2:
                let a = m.points[0].cg
                let b = m.points[1].cg
                total += Double(abs(b.x - a.x) * abs(b.y - a.y)) / (pxPerFt * pxPerFt)
            case .polygon where m.points.count >= 3:
                total += polygonAreaSqFt(m.points.map(\.cg), pixelsPerFoot: pxPerFt)
            default:
                break
            }
        }
        return total
    }
}

private struct BlueprintThumbnail: View {
    let blueprint: Blueprint
    let size: CGFloat
    var onDelete: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                ZStack(alignment: .bottomLeading) {
                    if let firstPage = blueprint.sortedPages.first,
                       let img = PlatformImage.image(from: firstPage.imageData) {
                        img
                            .resizable()
                            .scaledToFill()
                            .frame(width: size, height: size)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(white: 0.85), lineWidth: 0.5)
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(white: 0.92))
                            .frame(width: size, height: size)
                            .overlay(Image(systemName: "doc").foregroundStyle(.secondary))
                    }

                    HStack(spacing: 4) {
                        Image(systemName: blueprint.isCalibrated ? "ruler.fill" : "ruler")
                        Text(blueprint.isCalibrated ? "Calibrated" : "Set scale")
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.55), in: Capsule())
                    .padding(6)

                    // Page count pill in bottom-right.
                    HStack {
                        Spacer()
                        Text("\(blueprint.pages.count) page\(blueprint.pages.count == 1 ? "" : "s")")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.ecoNavy.opacity(0.85), in: Capsule())
                            .padding(6)
                    }
                }

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .red)
                        .padding(4)
                }
                .buttonStyle(.plain)
            }
            if !blueprint.caption.isEmpty {
                Text(blueprint.caption)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(width: size)
            }
            let mcount = blueprint.pages.reduce(0) { $0 + $1.measurements.count }
            Text(mcount == 0 ? "No measurements" : "\(mcount) measurement\(mcount == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

/// Free helper reused by both the section footer and takeoff editor totals.
func polygonAreaSqFt(_ points: [CGPoint], pixelsPerFoot: Double) -> Double {
    guard pixelsPerFoot > 0, points.count >= 3 else { return 0 }
    var sum = 0.0
    for i in 0..<points.count {
        let a = points[i]
        let b = points[(i + 1) % points.count]
        sum += Double(a.x * b.y - b.x * a.y)
    }
    return abs(sum) / 2 / (pixelsPerFoot * pixelsPerFoot)
}
