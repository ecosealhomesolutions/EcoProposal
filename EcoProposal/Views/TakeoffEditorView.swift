import SwiftUI
import SwiftData

/// Paged takeoff surface. One plan set contains many pages that all share ONE
/// calibration — set the scale once, measure across every sheet. Line, Rectangle,
/// and Bluebeam-style polygon tools with pinch-zoom + pan.
struct TakeoffEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var blueprint: Blueprint

    enum Tool: String, CaseIterable, Identifiable {
        case calibrate, line, rectangle, polygon
        var id: String { rawValue }
        var label: String {
            switch self {
            case .calibrate: return "Calibrate"
            case .line:      return "Line"
            case .rectangle: return "Rectangle"
            case .polygon:   return "Polygon"
            }
        }
        var systemImage: String {
            switch self {
            case .calibrate: return "ruler"
            case .line:      return "line.diagonal"
            case .rectangle: return "rectangle"
            case .polygon:   return "hexagon"
            }
        }
    }

    @State private var activeTool: Tool = .line
    @State private var pendingFirstPoint: CGPoint?
    @State private var polygonVertices: [CGPoint] = []
    @State private var calibrationEndpoints: (CGPoint, CGPoint)?
    @State private var calibrationFeetText: String = ""
    @State private var showingClearConfirmation = false
    @State private var recentMeasurement: String?
    @State private var pdfScaleSuggestion: DetectedScale?
    @State private var currentPageIndex: Int = 0
    @State private var showingScaleTextInput = false
    @State private var scaleTextInput: String = ""

    // Zoom + pan state, per-page. Reset when swapping pages.
    @State private var zoom: CGFloat = 1.0
    @State private var pan: CGSize = .zero
    @GestureState private var pinchDelta: CGFloat = 1.0
    @GestureState private var dragDelta: CGSize = .zero

    private var effectiveZoom: CGFloat { max(1.0, min(6.0, zoom * pinchDelta)) }
    private var effectivePan: CGSize {
        CGSize(width: pan.width + dragDelta.width, height: pan.height + dragDelta.height)
    }

    private var pages: [BlueprintPage] { blueprint.sortedPages }
    private var currentPage: BlueprintPage? {
        guard currentPageIndex >= 0, currentPageIndex < pages.count else { return nil }
        return pages[currentPageIndex]
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            canvasArea
            pageBar
            measurementReadout
        }
        .navigationTitle(blueprint.caption.isEmpty ? "Takeoff" : blueprint.caption)
        .iosInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !polygonVertices.isEmpty {
                    Button {
                        commitPolygon()
                    } label: {
                        Label("Close polygon", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(polygonVertices.count < 3)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if !polygonVertices.isEmpty {
                        Button("Cancel current polygon", role: .destructive) {
                            polygonVertices = []
                        }
                    }
                    Button("Reset zoom") { resetZoom() }
                    Divider()
                    Button("Clear this page's measurements", role: .destructive) {
                        showingClearConfirmation = true
                    }
                } label: {
                    Label("More…", systemImage: "ellipsis.circle")
                }
            }
        }
        .alert(
            "Enter real distance",
            isPresented: Binding(
                get: { calibrationEndpoints != nil },
                set: { if !$0 { cancelCalibration() } }
            )
        ) {
            TextField("Feet", text: $calibrationFeetText)
                .iosKeyboardType(.decimal)
            Button("Set scale") {
                if let (a, b) = calibrationEndpoints,
                   let feet = Double(calibrationFeetText), feet > 0 {
                    applyCalibration(a: a, b: b, feet: feet)
                }
                cancelCalibration()
            }
            Button("Cancel", role: .cancel) {
                cancelCalibration()
            }
        } message: {
            Text("You marked a line. What's its real-world length in feet? This calibrates every page of the plan set.")
        }
        .alert(
            "Use scale from plan?",
            isPresented: Binding(
                get: { pdfScaleSuggestion != nil },
                set: { if !$0 { pdfScaleSuggestion = nil } }
            )
        ) {
            Button("Use this scale") {
                if let s = pdfScaleSuggestion {
                    applyDetectedScale(s)
                }
                pdfScaleSuggestion = nil
            }
            Button("Calibrate manually", role: .cancel) {
                pdfScaleSuggestion = nil
            }
        } message: {
            if let s = pdfScaleSuggestion {
                Text("The plan appears to be at \(s.humanLabel). Use this as the scale (applied to all pages), or calibrate manually.")
            }
        }
        .alert(
            "Enter plan scale",
            isPresented: $showingScaleTextInput
        ) {
            TextField("e.g. 1/4\" = 1'", text: $scaleTextInput)
                .iosNoAutocapitalization()
            Button("Set scale") {
                applyScaleFromText(scaleTextInput)
                showingScaleTextInput = false
            }
            Button("Cancel", role: .cancel) {
                showingScaleTextInput = false
            }
        } message: {
            Text("Type the architectural scale — for example `1/4\" = 1'` or `1/8\" = 1'-0\"`. This applies to every page of the plan set.")
        }
        .confirmationDialog(
            "Clear this page's measurements?",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) {
                currentPage?.measurements = []
                currentPage?.updatedAt = Date()
                polygonVertices = []
                pendingFirstPoint = nil
                try? modelContext.save()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Removes lines, rectangles, and polygons on this page only. Calibration stays. Other pages are untouched.")
        }
        .onAppear {
            offerPDFScaleIfPresent()
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            ForEach(Tool.allCases) { tool in
                Button {
                    switchTo(tool)
                } label: {
                    Label(tool.label, systemImage: tool.systemImage)
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .tint(activeTool == tool ? Color.ecoNavy : .secondary)
                .fixedSize()
            }
            Button {
                undoLastMeasurement()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.bordered)
            .tint(.orange)
            .fixedSize()
            .disabled(currentPage?.measurements.isEmpty ?? true)
            Spacer()
            zoomControls
            calibrationBadge
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(white: 0.96))
    }

    private var zoomControls: some View {
        HStack(spacing: 4) {
            Button { zoom = max(1.0, zoom - 0.5); clampPan() } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.bordered)
            Text(String(format: "%.1f×", effectiveZoom))
                .font(.caption.monospacedDigit())
                .frame(width: 42)
            Button { zoom = min(6.0, zoom + 0.5) } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.bordered)
            Button { resetZoom() } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.bordered)
            .disabled(zoom == 1.0 && pan == .zero)
        }
    }

    private var calibrationBadge: some View {
        Button {
            scaleTextInput = blueprint.detectedPDFScale ?? "1/4\" = 1'"
            showingScaleTextInput = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: blueprint.isCalibrated ? "checkmark.seal.fill" : "ruler")
                    .font(.footnote)
                    .foregroundStyle(blueprint.isCalibrated ? Color.ecoGreen : Color.ecoNavy)
                Text(scaleBadgeLabel)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(blueprint.isCalibrated ? .primary : Color.ecoNavy)
                    .fixedSize()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(Color.white)
            )
            .overlay(
                Capsule().stroke(blueprint.isCalibrated ? Color.ecoGreen.opacity(0.5) : Color.ecoNavy.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

    private var scaleBadgeLabel: String {
        if blueprint.isCalibrated {
            // Prefer the detected/human scale if we have it, otherwise show px/ft.
            if let raw = blueprint.detectedPDFScale,
               let parsed = DetectedScale.parse(raw, rasterizationScale: blueprint.pdfRasterizationScale ?? 1) {
                return parsed.humanLabel
            }
            return String(format: "%.1f px/ft", blueprint.pixelsPerFoot ?? 0)
        }
        return "Set scale"
    }

    // MARK: - Page navigation

    @ViewBuilder
    private var pageBar: some View {
        if pages.count > 1 {
            HStack(spacing: 12) {
                Button {
                    goToPage(currentPageIndex - 1)
                } label: {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.title2)
                }
                .disabled(currentPageIndex == 0)

                Text("Page \(currentPageIndex + 1) of \(pages.count)")
                    .font(.subheadline.weight(.medium))

                Button {
                    goToPage(currentPageIndex + 1)
                } label: {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.title2)
                }
                .disabled(currentPageIndex >= pages.count - 1)

                Spacer()

                // Compact thumbnail strip for quick jumping.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(pages.enumerated()), id: \.element.id) { idx, page in
                            Button {
                                goToPage(idx)
                            } label: {
                                if let img = PlatformImage.image(from: page.imageData) {
                                    img.resizable().scaledToFill()
                                        .frame(width: 40, height: 40)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(idx == currentPageIndex ? Color.ecoNavy : Color.gray.opacity(0.3),
                                                        lineWidth: idx == currentPageIndex ? 2 : 0.5)
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxWidth: 300)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(white: 0.94))
        }
    }

    private func goToPage(_ idx: Int) {
        guard idx >= 0, idx < pages.count else { return }
        currentPageIndex = idx
        pendingFirstPoint = nil
        polygonVertices = []
        resetZoom()
    }

    // MARK: - Canvas

    private var canvasArea: some View {
        GeometryReader { proxy in
            let containerSize = proxy.size
            let containerCenter = CGPoint(x: containerSize.width / 2, y: containerSize.height / 2)

            ZStack {
                Color(white: 0.94)

                if let page = currentPage,
                   let native = PlatformImage.uiImage(from: page.imageData) {
                    let imgSize = CGSize(width: native.size.width, height: native.size.height)
                    let fit = fittedRect(image: imgSize, in: containerSize)

                    ZStack {
                        Image(uiImage: native)
                            .resizable()
                            .frame(width: fit.width, height: fit.height)
                            .position(x: fit.midX, y: fit.midY)

                        MeasurementsOverlay(
                            measurements: page.measurements,
                            pixelsPerFoot: blueprint.pixelsPerFoot,
                            imageSize: imgSize,
                            displayRect: fit
                        )

                        if !polygonVertices.isEmpty {
                            InProgressPolygon(
                                vertices: polygonVertices,
                                imageSize: imgSize,
                                displayRect: fit
                            )
                        }

                        if let p = pendingFirstPoint {
                            let displayPoint = imageToDisplay(p, image: imgSize, display: fit)
                            Circle()
                                .fill(Color.ecoNavy)
                                .frame(width: 14, height: 14)
                                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                                .position(displayPoint)
                        }
                    }
                    .scaleEffect(effectiveZoom, anchor: .center)
                    .offset(effectivePan)
                    .allowsHitTesting(false)

                    // Tap catcher + pinch + drag on the un-transformed layer.
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            SpatialTapGesture(coordinateSpace: .local)
                                .onEnded { event in
                                    let untransformed = inverseTransform(
                                        tap: event.location,
                                        containerCenter: containerCenter
                                    )
                                    guard fit.contains(untransformed) else { return }
                                    let imagePoint = displayToImage(untransformed, image: imgSize, display: fit)
                                    handleTap(at: imagePoint)
                                }
                        )
                        .simultaneousGesture(
                            MagnificationGesture(minimumScaleDelta: 0.05)
                                .updating($pinchDelta) { value, state, _ in state = value }
                                .onEnded { value in
                                    zoom = max(1.0, min(6.0, zoom * value))
                                    clampPan()
                                }
                        )
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 12)
                                .updating($dragDelta) { value, state, _ in state = value.translation }
                                .onEnded { value in
                                    pan.width += value.translation.width
                                    pan.height += value.translation.height
                                    clampPan()
                                }
                        )
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "doc").font(.largeTitle)
                        Text("No page to display.")
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        // Bound the canvas so pan/zoom can't spill into the toolbar or readout.
        .clipped()
    }

    // MARK: - Readout

    private var measurementReadout: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let recentMeasurement {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.ecoGreen)
                    Text(recentMeasurement)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.ecoNavy)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.ecoGreen.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                .transition(.opacity)
            }
            if !blueprint.isCalibrated {
                Text("Tap the Calibrate tool, then tap two points on a known-length feature. One calibration applies to every page.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if !polygonVertices.isEmpty {
                Text("Polygon in progress — \(polygonVertices.count) vertex\(polygonVertices.count == 1 ? "" : "es") placed. Tap the green anchor (or ‘Close polygon’) to finish.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if pendingFirstPoint != nil {
                Text("Point 1 set. Tap point 2 to complete the \(activeTool.label.lowercased()).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if activeTool == .polygon {
                Text("Tap around the perimeter to place vertices. Tap the first vertex again (or ‘Close polygon’) to finish.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Tap two points to place a \(activeTool.label.lowercased()).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let pageArea = pageAreaSqFt(), pageArea > 0 {
                HStack {
                    Image(systemName: "square.dashed").foregroundStyle(Color.ecoNavy)
                    Text("This page:")
                        .font(.footnote)
                    Spacer()
                    Text("\(pageArea, specifier: "%.1f") sq ft")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Color.ecoNavy)
                }
            }
            if pages.count > 1, let totalArea = planSetAreaSqFt(), totalArea > 0 {
                HStack {
                    Image(systemName: "square.stack.3d.up.fill").foregroundStyle(Color.ecoNavy)
                    Text("All pages in this plan set:")
                        .font(.footnote)
                    Spacer()
                    Text("\(totalArea, specifier: "%.1f") sq ft")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Color.ecoNavy)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }

    private func pageAreaSqFt() -> Double? {
        guard let pxPerFt = blueprint.pixelsPerFoot, pxPerFt > 0,
              let page = currentPage else { return nil }
        return areaSqFt(measurements: page.measurements, pxPerFt: pxPerFt)
    }

    private func planSetAreaSqFt() -> Double? {
        guard let pxPerFt = blueprint.pixelsPerFoot, pxPerFt > 0 else { return nil }
        return blueprint.pages.reduce(0.0) { $0 + areaSqFt(measurements: $1.measurements, pxPerFt: pxPerFt) }
    }

    private func areaSqFt(measurements: [Measurement], pxPerFt: Double) -> Double {
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

    // MARK: - Tap handling

    private func switchTo(_ tool: Tool) {
        activeTool = tool
        pendingFirstPoint = nil
        polygonVertices = []
    }

    private func handleTap(at imagePoint: CGPoint) {
        guard let page = currentPage else { return }

        switch activeTool {
        case .calibrate, .line, .rectangle:
            if let first = pendingFirstPoint {
                switch activeTool {
                case .calibrate:
                    calibrationEndpoints = (first, imagePoint)
                    calibrationFeetText = ""
                case .line:
                    let m = Measurement(kind: .line, points: [first, imagePoint])
                    appendMeasurement(m, to: page)
                    flashLineMeasurement(m: m)
                case .rectangle:
                    var m = Measurement(kind: .rectangle, points: [first, imagePoint])
                    m.lineItemID = addLineItemIfAreaMeasurement(m)
                    appendMeasurement(m, to: page)
                    flashRectangleMeasurement(m: m)
                case .polygon:
                    break
                }
                pendingFirstPoint = nil
            } else {
                pendingFirstPoint = imagePoint
            }

        case .polygon:
            if polygonVertices.count >= 3,
               let first = polygonVertices.first,
               distance(first, imagePoint) < snapRadiusInImageSpace {
                commitPolygon()
                return
            }
            polygonVertices.append(imagePoint)
        }
    }

    private func commitPolygon() {
        guard polygonVertices.count >= 3, let page = currentPage else { return }
        var m = Measurement(kind: .polygon, points: polygonVertices)
        m.lineItemID = addLineItemIfAreaMeasurement(m)
        appendMeasurement(m, to: page)
        flashPolygonMeasurement(m: m)
        polygonVertices = []
    }

    /// If the plan set is calibrated and the measurement is a polygon or rectangle,
    /// drop a corresponding LineItem on the proposal — quantity = sq ft, unit price
    /// blank for the rep to fill in. Returns the new LineItem's UUID so Undo can
    /// clean up both the measurement AND its line item together.
    @discardableResult
    private func addLineItemIfAreaMeasurement(_ m: Measurement) -> UUID? {
        guard let proposal = blueprint.proposal,
              let pxPerFt = blueprint.pixelsPerFoot,
              pxPerFt > 0 else { return nil }
        let pageLabel = "Page \(currentPageIndex + 1)"
        let planLabel = blueprint.caption.isEmpty ? "Plan set" : blueprint.caption
        let sqFt: Double
        let kindLabel: String
        switch m.kind {
        case .rectangle where m.points.count >= 2:
            let a = m.points[0].cg
            let b = m.points[1].cg
            sqFt = Double(abs(b.x - a.x) * abs(b.y - a.y)) / (pxPerFt * pxPerFt)
            kindLabel = "Rectangle"
        case .polygon where m.points.count >= 3:
            sqFt = polygonAreaSqFt(m.points.map(\.cg), pixelsPerFoot: pxPerFt)
            kindLabel = "Polygon"
        default:
            return nil
        }
        let description = "\(kindLabel) — \(planLabel) \(pageLabel)"
        let nextSort = (proposal.lineItems.map(\.sortOrder).max() ?? -1) + 1
        let lineItem = LineItem(
            descriptionText: description,
            quantity: sqFt,
            unitPrice: 0,
            unit: "sq ft",
            sortOrder: nextSort,
            proposal: proposal
        )
        modelContext.insert(lineItem)
        proposal.lineItems.append(lineItem)
        try? modelContext.save()
        return lineItem.id
    }

    /// Pops the most recent measurement on the current page and — if it created
    /// a line item — deletes that too. Effectively a one-tap "oops" button.
    private func undoLastMeasurement() {
        guard let page = currentPage else { return }
        var list = page.measurements
        guard !list.isEmpty else { return }
        let removed = list.removeLast()
        page.measurements = list
        page.updatedAt = Date()

        // Also drop the linked LineItem, if any.
        if let lineItemID = removed.lineItemID,
           let proposal = blueprint.proposal,
           let idx = proposal.lineItems.firstIndex(where: { $0.id == lineItemID }) {
            let li = proposal.lineItems[idx]
            proposal.lineItems.remove(at: idx)
            modelContext.delete(li)
        }

        // If we undid the calibration measurement, drop the derived scale too.
        if removed.kind == .calibration {
            blueprint.pixelsPerFoot = nil
        }

        blueprint.updatedAt = Date()
        try? modelContext.save()
        flashMessage("Undid \(kindLabel(removed.kind))")
    }

    private func kindLabel(_ k: Measurement.Kind) -> String {
        switch k {
        case .line:        return "line"
        case .rectangle:   return "rectangle"
        case .polygon:     return "polygon"
        case .calibration: return "calibration"
        }
    }

    private func cancelCalibration() {
        calibrationEndpoints = nil
        calibrationFeetText = ""
    }

    private func appendMeasurement(_ m: Measurement, to page: BlueprintPage) {
        var list = page.measurements
        list.append(m)
        page.measurements = list
        page.updatedAt = Date()
        blueprint.updatedAt = Date()
        try? modelContext.save()
    }

    private func applyCalibration(a: CGPoint, b: CGPoint, feet: Double) {
        guard let page = currentPage else { return }
        let dx = b.x - a.x
        let dy = b.y - a.y
        let pixels = sqrt(dx * dx + dy * dy)
        guard pixels > 0 else { return }
        blueprint.pixelsPerFoot = pixels / feet
        blueprint.updatedAt = Date()
        // Store the calibration reference line on the page it was drawn on.
        appendMeasurement(Measurement(kind: .calibration, points: [a, b], label: "\(feet) ft"), to: page)
        activeTool = .line
        flashMessage("Scale set: \(feet) ft between the two points. Applies to every page.")
    }

    private func offerPDFScaleIfPresent() {
        guard !blueprint.isCalibrated else { return }
        guard let rasterScale = blueprint.pdfRasterizationScale, rasterScale > 0 else { return }
        guard let raw = blueprint.detectedPDFScale,
              let parsed = DetectedScale.parse(raw, rasterizationScale: rasterScale)
        else { return }
        pdfScaleSuggestion = parsed
    }

    private func applyDetectedScale(_ s: DetectedScale) {
        blueprint.pixelsPerFoot = s.pixelsPerFoot
        blueprint.updatedAt = Date()
        try? modelContext.save()
        flashMessage("Calibrated from plan scale: \(s.humanLabel)")
    }

    /// Ratio-driven scale set — e.g. rep types `1/4" = 1'` and we compute pixels-per-foot
    /// from the PDF's rasterization scale (72 pt/inch × raster factor × inches-per-foot).
    private func applyScaleFromText(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let rasterScale = blueprint.pdfRasterizationScale, rasterScale > 0 else {
            flashMessage("Ratio-based scale only works for PDF imports. Use the Calibrate tool for image uploads.")
            return
        }
        guard let s = DetectedScale.parse(trimmed, rasterizationScale: rasterScale) else {
            flashMessage("Couldn't parse ‘\(trimmed)’. Try a form like 1/4\" = 1' or 1/8\" = 1'.")
            return
        }
        blueprint.pixelsPerFoot = s.pixelsPerFoot
        blueprint.updatedAt = Date()
        try? modelContext.save()
        flashMessage("Scale set to \(s.humanLabel).")
    }

    // MARK: - Flash

    private func flashLineMeasurement(m: Measurement) {
        guard let pxPerFt = blueprint.pixelsPerFoot, pxPerFt > 0, m.points.count >= 2 else { return }
        let a = m.points[0].cg
        let b = m.points[1].cg
        let dx = b.x - a.x
        let dy = b.y - a.y
        let feet = sqrt(Double(dx * dx + dy * dy)) / pxPerFt
        flashMessage(String(format: "Line: %.1f ft", feet))
    }

    private func flashRectangleMeasurement(m: Measurement) {
        guard let pxPerFt = blueprint.pixelsPerFoot, pxPerFt > 0, m.points.count >= 2 else { return }
        let a = m.points[0].cg
        let b = m.points[1].cg
        let w = Double(abs(b.x - a.x)) / pxPerFt
        let h = Double(abs(b.y - a.y)) / pxPerFt
        let addedNote = blueprint.proposal != nil ? " · added to line items" : ""
        flashMessage(String(format: "Rectangle: %.1f × %.1f = %.1f sq ft%@", w, h, w * h, addedNote))
    }

    private func flashPolygonMeasurement(m: Measurement) {
        guard let pxPerFt = blueprint.pixelsPerFoot, pxPerFt > 0 else { return }
        let pts = m.points.map(\.cg)
        let area = polygonAreaSqFt(pts, pixelsPerFoot: pxPerFt)
        let perim = polygonPerimeterPixels(pts, closed: true) / pxPerFt
        let addedNote = blueprint.proposal != nil ? " · added to line items" : ""
        flashMessage(String(format: "Polygon: %.1f sq ft • %.1f ft perimeter%@", area, perim, addedNote))
    }

    private func flashMessage(_ text: String) {
        recentMeasurement = text
        Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            await MainActor.run {
                if recentMeasurement == text { recentMeasurement = nil }
            }
        }
    }

    // MARK: - Zoom helpers

    private func resetZoom() {
        withAnimation(.easeInOut(duration: 0.2)) {
            zoom = 1.0
            pan = .zero
        }
    }

    private func clampPan() {
        let maxOffset: CGFloat = 400 * effectiveZoom
        pan.width = max(-maxOffset, min(maxOffset, pan.width))
        pan.height = max(-maxOffset, min(maxOffset, pan.height))
    }

    private var snapRadiusInImageSpace: CGFloat {
        let screenSnap: CGFloat = 22
        return screenSnap / max(0.5, effectiveZoom) * 1.5
    }

    // MARK: - Coordinate math

    private func fittedRect(image: CGSize, in container: CGSize) -> CGRect {
        guard image.width > 0, image.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        let scale = min(container.width / image.width, container.height / image.height)
        let w = image.width * scale
        let h = image.height * scale
        return CGRect(
            x: (container.width - w) / 2,
            y: (container.height - h) / 2,
            width: w,
            height: h
        )
    }

    private func displayToImage(_ p: CGPoint, image: CGSize, display: CGRect) -> CGPoint {
        let normX = (p.x - display.minX) / display.width
        let normY = (p.y - display.minY) / display.height
        return CGPoint(x: normX * image.width, y: normY * image.height)
    }

    private func imageToDisplay(_ p: CGPoint, image: CGSize, display: CGRect) -> CGPoint {
        let x = display.minX + (p.x / image.width) * display.width
        let y = display.minY + (p.y / image.height) * display.height
        return CGPoint(x: x, y: y)
    }

    private func inverseTransform(tap: CGPoint, containerCenter: CGPoint) -> CGPoint {
        let s = effectiveZoom
        let o = effectivePan
        let x = (tap.x - o.width - containerCenter.x) / s + containerCenter.x
        let y = (tap.y - o.height - containerCenter.y) / s + containerCenter.y
        return CGPoint(x: x, y: y)
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }
}

// MARK: - Detected PDF scale

struct DetectedScale {
    let humanLabel: String
    let inchesPerFoot: Double
    let pixelsPerFoot: Double

    static func parse(_ raw: String, rasterizationScale: Double) -> DetectedScale? {
        let pattern = #"([0-9]+)(?:/([0-9]+))?"?\s*=\s*([0-9]+)\s*'"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        guard let match = regex.firstMatch(in: raw, range: range) else { return nil }

        func group(_ i: Int) -> String? {
            guard let r = Range(match.range(at: i), in: raw) else { return nil }
            return String(raw[r])
        }

        guard let numStr = group(1), let num = Double(numStr) else { return nil }
        let den = Double(group(2) ?? "1") ?? 1
        guard let feetStr = group(3), let feet = Double(feetStr), feet > 0 else { return nil }
        let inches = num / den
        let inchesPerFoot = inches / feet

        let pixelsPerInch = 72.0 * rasterizationScale
        let pixelsPerFoot = inchesPerFoot * pixelsPerInch

        let denomLabel = (den == 1) ? "\(Int(num))" : "\(Int(num))/\(Int(den))"
        let label = "\(denomLabel)\" = \(Int(feet))'"
        return DetectedScale(humanLabel: label, inchesPerFoot: inchesPerFoot, pixelsPerFoot: pixelsPerFoot)
    }
}

// MARK: - Shoelace helpers

private func polygonAreaPixels(_ points: [CGPoint]) -> Double {
    guard points.count >= 3 else { return 0 }
    var sum = 0.0
    for i in 0..<points.count {
        let a = points[i]
        let b = points[(i + 1) % points.count]
        sum += Double(a.x * b.y - b.x * a.y)
    }
    return abs(sum) / 2
}

func polygonPerimeterPixels(_ points: [CGPoint], closed: Bool) -> Double {
    guard points.count >= 2 else { return 0 }
    var total = 0.0
    let n = points.count
    let last = closed ? n : n - 1
    for i in 0..<last {
        let a = points[i]
        let b = points[(i + 1) % n]
        let dx = a.x - b.x
        let dy = a.y - b.y
        total += sqrt(Double(dx * dx + dy * dy))
    }
    return total
}

// MARK: - In-progress polygon

private struct InProgressPolygon: View {
    let vertices: [CGPoint]
    let imageSize: CGSize
    let displayRect: CGRect

    var body: some View {
        ZStack {
            Path { path in
                let displayed = vertices.map { toDisplay($0) }
                guard let first = displayed.first else { return }
                path.move(to: first)
                for p in displayed.dropFirst() {
                    path.addLine(to: p)
                }
            }
            .stroke(Color.ecoNavy, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

            ForEach(Array(vertices.enumerated()), id: \.offset) { idx, v in
                let displayed = toDisplay(v)
                if idx == 0 {
                    ZStack {
                        Circle().fill(Color.ecoGreen).frame(width: 16, height: 16)
                        Circle().stroke(Color.white, lineWidth: 2).frame(width: 16, height: 16)
                    }
                    .position(displayed)
                } else {
                    Circle().fill(Color.ecoNavy).frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                        .position(displayed)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func toDisplay(_ p: CGPoint) -> CGPoint {
        let x = displayRect.minX + (p.x / imageSize.width) * displayRect.width
        let y = displayRect.minY + (p.y / imageSize.height) * displayRect.height
        return CGPoint(x: x, y: y)
    }
}

// MARK: - Measurement overlay

private struct MeasurementsOverlay: View {
    let measurements: [Measurement]
    let pixelsPerFoot: Double?
    let imageSize: CGSize
    let displayRect: CGRect

    var body: some View {
        ZStack {
            ForEach(measurements) { m in
                shape(for: m)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func shape(for m: Measurement) -> some View {
        switch m.kind {
        case .line, .calibration:
            if m.points.count >= 2 {
                lineShape(m: m, a: m.points[0].cg, b: m.points[1].cg)
            }
        case .rectangle:
            if m.points.count >= 2 {
                rectangleShape(m: m, a: m.points[0].cg, b: m.points[1].cg)
            }
        case .polygon:
            if m.points.count >= 3 {
                polygonShape(m: m)
            }
        }
    }

    private func lineShape(m: Measurement, a rawA: CGPoint, b rawB: CGPoint) -> some View {
        let a = toDisplay(rawA)
        let b = toDisplay(rawB)
        let color: Color = (m.kind == .calibration) ? .orange : Color.ecoNavy
        return ZStack {
            Path { p in
                p.move(to: a)
                p.addLine(to: b)
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: m.kind == .calibration ? [4, 3] : []))

            if let label = lineLabel(m: m, a: rawA, b: rawB) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 4))
                    .position(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            }
        }
    }

    private func rectangleShape(m: Measurement, a rawA: CGPoint, b rawB: CGPoint) -> some View {
        let a = toDisplay(rawA)
        let b = toDisplay(rawB)
        let rect = CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(b.x - a.x),
            height: abs(b.y - a.y)
        )
        return ZStack {
            Rectangle()
                .strokeBorder(Color.ecoGreen, style: StrokeStyle(lineWidth: 2))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
            Rectangle()
                .fill(Color.ecoGreen.opacity(0.15))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
            if let label = rectLabel(a: rawA, b: rawB) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.ecoGreen)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 4))
                    .position(x: rect.midX, y: rect.midY)
            }
        }
    }

    private func polygonShape(m: Measurement) -> some View {
        let displayed = m.points.map { toDisplay($0.cg) }
        let centroid = polygonCentroid(displayed)
        return ZStack {
            Path { path in
                guard let first = displayed.first else { return }
                path.move(to: first)
                for p in displayed.dropFirst() { path.addLine(to: p) }
                path.closeSubpath()
            }
            .fill(Color.ecoGreen.opacity(0.14))
            Path { path in
                guard let first = displayed.first else { return }
                path.move(to: first)
                for p in displayed.dropFirst() { path.addLine(to: p) }
                path.closeSubpath()
            }
            .stroke(Color.ecoGreen, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            if let label = polygonLabel(m: m) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.ecoGreen)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 4))
                    .position(centroid)
            }
        }
    }

    private func lineLabel(m: Measurement, a: CGPoint, b: CGPoint) -> String? {
        if m.kind == .calibration { return m.label }
        guard let pxPerFt = pixelsPerFoot, pxPerFt > 0 else { return nil }
        let dx = b.x - a.x
        let dy = b.y - a.y
        let feet = sqrt(Double(dx * dx + dy * dy)) / pxPerFt
        return String(format: "%.1f ft", feet)
    }

    private func rectLabel(a: CGPoint, b: CGPoint) -> String? {
        guard let pxPerFt = pixelsPerFoot, pxPerFt > 0 else { return nil }
        let w = Double(abs(b.x - a.x)) / pxPerFt
        let h = Double(abs(b.y - a.y)) / pxPerFt
        let area = w * h
        return String(format: "%.1f × %.1f = %.1f sq ft", w, h, area)
    }

    private func polygonLabel(m: Measurement) -> String? {
        guard let pxPerFt = pixelsPerFoot, pxPerFt > 0 else { return nil }
        let pts = m.points.map(\.cg)
        let area = polygonAreaSqFt(pts, pixelsPerFoot: pxPerFt)
        let perim = polygonPerimeterPixels(pts, closed: true) / pxPerFt
        return String(format: "%.1f sq ft\n(%.1f ft perim)", area, perim)
    }

    private func polygonCentroid(_ pts: [CGPoint]) -> CGPoint {
        guard !pts.isEmpty else { return .zero }
        let xs = pts.map { Double($0.x) }.reduce(0, +) / Double(pts.count)
        let ys = pts.map { Double($0.y) }.reduce(0, +) / Double(pts.count)
        return CGPoint(x: xs, y: ys)
    }

    private func toDisplay(_ p: CGPoint) -> CGPoint {
        let x = displayRect.minX + (p.x / imageSize.width) * displayRect.width
        let y = displayRect.minY + (p.y / imageSize.height) * displayRect.height
        return CGPoint(x: x, y: y)
    }
}
