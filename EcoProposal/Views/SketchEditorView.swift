import SwiftUI
import SwiftData

#if canImport(PencilKit) && os(iOS)
import PencilKit
#endif

/// Full-screen editor: PencilKit canvas over a graph-paper background, with
/// compass labels (BACK/RIGHT/FRONT/LEFT) outside the grid and a toolbar for
/// stamping basic shapes and text notes onto the sketch.
struct SketchEditorView: View {
    /// Active canvas tool. `.ink` is PencilKit freehand; the others capture drags
    /// on an overlay above the canvas.
    enum SketchTool: String, CaseIterable {
        case ink, walls, crack, erase

        var title: String {
            switch self {
            case .ink:   return "Draw"
            case .walls: return "Walls"
            case .crack: return "Crack"
            case .erase: return "Erase"
            }
        }

        var systemImage: String {
            switch self {
            case .ink:   return "pencil.tip"
            case .walls: return "line.diagonal"
            case .crack: return "bolt"
            case .erase: return "eraser"
            }
        }
    }

    /// Snapshot of canvas content for undo (ink included so Clear is undoable).
    private struct VectorState {
        var ink: Data?
        var annotations: [SketchAnnotation]
        var segments: [SketchSegment]
        var cracks: [SketchCrack]
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var proposal: Proposal

    @State private var draftInk: Data?
    @State private var annotations: [SketchAnnotation]
    @State private var segments: [SketchSegment]
    @State private var cracks: [SketchCrack]
    @State private var selectedID: UUID?
    @State private var selectedSegmentID: UUID?
    @State private var pendingNoteText: String = ""
    @State private var showingNoteEntry: Bool = false
    /// When set, the note entry alert is editing this existing annotation's text
    /// instead of creating a new note.
    @State private var editingNoteID: UUID?
    /// Gives the canvas keyboard focus so hardware arrow keys nudge the selected
    /// annotation (iPad with an external keyboard).
    @FocusState private var canvasFocused: Bool

    // Tool state
    @State private var tool: SketchTool = .ink
    @State private var angleSnapEnabled = true
    @State private var undoStack: [VectorState] = []

    // In-progress gesture state
    @State private var draftWallStart: CGPoint?
    @State private var draftWallEnd: CGPoint?
    @State private var snapIndicator: CGPoint?
    @State private var draftCrackPoints: [CGPoint] = []
    @State private var eraserPoints: [CGPoint] = []

    /// Committed pinch-zoom level; `pinchMagnification` rides on top mid-gesture.
    @State private var baseZoom: CGFloat = 1
    @GestureState private var pinchMagnification: CGFloat = 1

    init(proposal: Proposal) {
        self.proposal = proposal
        // Seed state from the model at init time so the PKCanvasView is created with
        // the existing drawing already loaded — avoids a race where the empty canvas's
        // delegate fires and clobbers `draftInk` before `.onAppear` can restore it.
        _draftInk = State(initialValue: proposal.sketchData)
        _annotations = State(
            initialValue: SketchAnnotationsCodec.decode(proposal.sketchAnnotationsData)
        )
        _segments = State(
            initialValue: SketchGeometryCodec.decodeSegments(proposal.sketchSegmentsData)
        )
        _cracks = State(
            initialValue: SketchGeometryCodec.decodeCracks(proposal.sketchCracksData)
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                toolbar
                Divider()
                canvasLayer
                    .background(Color.white)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedID = nil; selectedSegmentID = nil } // tap empty canvas to deselect
                    // Arrow keys on an external keyboard nudge the selected item.
                    .focusable()
                    .focused($canvasFocused)
                    .onKeyPress(.upArrow) { nudge(dx: 0, dy: -nudgeStep) ? .handled : .ignored }
                    .onKeyPress(.downArrow) { nudge(dx: 0, dy: nudgeStep) ? .handled : .ignored }
                    .onKeyPress(.leftArrow) { nudge(dx: -nudgeStep, dy: 0) ? .handled : .ignored }
                    .onKeyPress(.rightArrow) { nudge(dx: nudgeStep, dy: 0) ? .handled : .ignored }
            }
            .navigationTitle("Job Sketch")
            .iosInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save") { save() }
                        .buttonStyle(.borderedProminent)
                }
                ToolbarItem(placement: .leadingCompat) {
                    Button(role: .destructive) {
                        pushUndo()
                        draftInk = nil
                        annotations = []
                        segments = []
                        cracks = []
                        selectedID = nil
                        selectedSegmentID = nil
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                }
                ToolbarItem(placement: .leadingCompat) {
                    Button {
                        popUndo()
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(undoStack.isEmpty)
                }
            }
            .alert(editingNoteID == nil ? "Add note" : "Edit note", isPresented: $showingNoteEntry) {
                TextField("Note", text: $pendingNoteText)
                Button(editingNoteID == nil ? "Add" : "Save") { commitNote() }
                Button("Cancel", role: .cancel) {
                    pendingNoteText = ""
                    editingNoteID = nil
                }
            } message: {
                Text(editingNoteID == nil
                     ? "Type a short note to place on the sketch. Drag it after adding — tap it again to edit."
                     : "Update the note text.")
            }
        }
        .onAppear {
            // Belt-and-suspenders: force-restore state from the model in case the
            // @State initializer wasn't respected (e.g., view identity reuse).
            if let saved = proposal.sketchData, !saved.isEmpty, draftInk == nil {
                draftInk = saved
            }
            let savedAnnotations = SketchAnnotationsCodec.decode(proposal.sketchAnnotationsData)
            if annotations.isEmpty && !savedAnnotations.isEmpty {
                annotations = savedAnnotations
            }
            // Take keyboard focus so arrow-key nudging works without a tap first.
            canvasFocused = true
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Tool modes
                ForEach(SketchTool.allCases, id: \.self) { candidate in
                    Button {
                        tool = candidate
                        selectedID = nil
                        selectedSegmentID = nil
                    } label: {
                        Label(candidate.title, systemImage: candidate.systemImage)
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered)
                    .tint(tool == candidate ? Color.ecoGreen : nil)
                    .fixedSize()
                }

                if tool == .walls {
                    Toggle(isOn: $angleSnapEnabled) {
                        Label("90°/45°", systemImage: "angle")
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .fixedSize()
                }

                Divider().frame(height: 24)

                shapeButton(kind: .rectangle, systemImage: "rectangle")
                shapeButton(kind: .circle, systemImage: "circle")
                shapeButton(kind: .line, systemImage: "arrow.left.and.right")
                shapeButton(kind: .arrow, systemImage: "arrow.right")
                shapeButton(kind: .pier, systemImage: "arrow.down.to.line")
                shapeButton(kind: .sumpPump, systemImage: "drop.circle")
                shapeButton(kind: .egressWindow, systemImage: "window.vertical.closed")
                shapeButton(kind: .carbonStrap, systemImage: "bandage")
                shapeButton(kind: .powerBrace, systemImage: "poweroutlet.type.i")
                shapeButton(kind: .stairs, systemImage: "stairs")
                Button {
                    editingNoteID = nil
                    pendingNoteText = ""
                    showingNoteEntry = true
                } label: {
                    Label("Note", systemImage: "note.text")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(white: 0.96))
    }

    private func shapeButton(kind: SketchAnnotation.Kind, systemImage: String) -> some View {
        Button {
            addShape(kind: kind)
        } label: {
            Label(kind.buttonTitle, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.bordered)
        .fixedSize()
    }

    // MARK: - Canvas layer

    private var canvasLayer: some View {
        GeometryReader { proxy in
            // Big content (e.g. a LiDAR floor plan of a whole house) free-scrolls in
            // both directions and pinch-zooms. The canvas is at least screen-sized
            // and grows to fit the sketch, so scrolling only kicks in when it's
            // actually needed. One finger draws, two fingers scroll, pinch zooms.
            let canvasSize = CGSize(
                width: max(proxy.size.width, requiredCanvasSize.width),
                height: max(proxy.size.height, requiredCanvasSize.height)
            )
            let liveZoom = clampedZoom(baseZoom * pinchMagnification)
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                CompassGridFrame {
                    ZStack(alignment: .topLeading) {
                        // PencilKit ink layer
                        DrawingCanvas(data: $draftInk)

                        // Wall segments + cracks (vector layers)
                        SegmentsLayer(segments: segments, selectedID: selectedSegmentID)
                            .allowsHitTesting(false)
                        CracksLayer(cracks: cracks)
                            .allowsHitTesting(false)

                        // Annotation overlay
                        ForEach($annotations) { $annotation in
                            AnnotationView(
                                annotation: $annotation,
                                isSelected: annotation.id == selectedID,
                                boundsSize: canvasSize,
                                zoomScale: liveZoom,
                                onSelect: {
                                    selectedID = annotation.id
                                    canvasFocused = true
                                },
                                onDelete: {
                                    delete(annotation.id)
                                },
                                onDuplicate: {
                                    duplicate(annotation.id)
                                },
                                onEdit: {
                                    beginEditingNote(annotation.id)
                                }
                            )
                        }

                        // When a non-ink tool is active, this overlay sits above
                        // everything and owns the drag. Local coordinates = raw
                        // canvas coordinates (scaleEffect maps touches back).
                        if tool != .ink {
                            Color.clear
                                .contentShape(Rectangle())
                                .gesture(toolGesture)
                        }

                        // Live previews + indicators
                        toolPreviewLayer
                            .allowsHitTesting(false)

                        // Delete handle for the selected wall segment
                        if tool == .walls, let selected = segments.first(where: { $0.id == selectedSegmentID }) {
                            Button {
                                deleteSelectedSegment()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 22))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, Color.red)
                            }
                            .buttonStyle(.plain)
                            .position(selected.point(at: 0.5))
                        }
                    }
                }
                .frame(width: canvasSize.width, height: canvasSize.height)
                // Scale the whole sheet (grid + ink + annotations together), then
                // reserve the scaled footprint so the scrollable range matches.
                .scaleEffect(liveZoom, anchor: .topLeading)
                .frame(
                    width: canvasSize.width * liveZoom,
                    height: canvasSize.height * liveZoom,
                    alignment: .topLeading
                )
            }
            .scrollBounceBehavior(.basedOnSize, axes: [.horizontal, .vertical])
            .simultaneousGesture(zoomGesture)
            .overlay(alignment: .bottomLeading) {
                if liveZoom != 1 {
                    Button {
                        baseZoom = 1
                    } label: {
                        Text("\(Int((liveZoom * 100).rounded()))%")
                            .font(.footnote.weight(.semibold).monospacedDigit())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(10)
                }
            }
        }
    }

    // MARK: - Zoom

    private static let zoomRange: ClosedRange<CGFloat> = 0.4...4

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .updating($pinchMagnification) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                baseZoom = clampedZoom(baseZoom * value.magnification)
            }
    }

    private func clampedZoom(_ value: CGFloat) -> CGFloat {
        min(max(value, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
    }

    // MARK: - Walls / Crack / Erase tools

    /// How close (canvas pt) a new wall endpoint must be to an existing endpoint to snap.
    private let endpointSnapDistance: CGFloat = 20
    /// Angle snap threshold, degrees from a 45° multiple.
    private let angleSnapThreshold: Double = 7

    private var toolGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                switch tool {
                case .walls:
                    if draftWallStart == nil {
                        let snapped = snapToEndpoint(value.startLocation)
                        draftWallStart = snapped ?? value.startLocation
                    }
                    updateDraftWallEnd(value.location)
                case .crack:
                    appendCrackPoint(value.location)
                case .erase:
                    eraserPoints.append(value.location)
                case .ink:
                    break
                }
            }
            .onEnded { value in
                switch tool {
                case .walls:
                    finishWallDrag(translation: value.translation, tapLocation: value.startLocation)
                case .crack:
                    finishCrackDrag()
                case .erase:
                    finishEraseDrag()
                case .ink:
                    break
                }
            }
    }

    /// Live preview of the in-progress wall / crack / eraser path, plus the
    /// green snap indicator.
    @ViewBuilder
    private var toolPreviewLayer: some View {
        if let start = draftWallStart, let end = draftWallEnd {
            Path { p in
                p.move(to: start)
                p.addLine(to: end)
            }
            .stroke(
                SketchGeometryStyle.wallColor.opacity(0.6),
                style: StrokeStyle(lineWidth: SketchGeometryStyle.wallWidth, lineCap: .round, dash: [6, 4])
            )
        }
        if let snapIndicator {
            Circle()
                .stroke(Color.ecoGreen, lineWidth: 2.5)
                .frame(width: 18, height: 18)
                .position(snapIndicator)
        }
        if draftCrackPoints.count >= 2 {
            Path { p in
                CrackShape.addZigzag(to: &p, along: draftCrackPoints)
            }
            .stroke(
                SketchGeometryStyle.crackColor.opacity(0.7),
                style: StrokeStyle(lineWidth: SketchGeometryStyle.crackWidth, lineCap: .round, lineJoin: .round)
            )
        }
        if eraserPoints.count >= 2 {
            Path { p in
                p.move(to: eraserPoints[0])
                for point in eraserPoints.dropFirst() { p.addLine(to: point) }
            }
            .stroke(
                Color.red.opacity(0.35),
                style: StrokeStyle(lineWidth: SketchEraser.radius * 2, lineCap: .round, lineJoin: .round)
            )
        }
    }

    /// All existing wall endpoints — snap targets for new segments.
    private var allEndpoints: [CGPoint] {
        segments.flatMap { [$0.start, $0.end] }
    }

    private func snapToEndpoint(_ point: CGPoint) -> CGPoint? {
        allEndpoints
            .map { ($0, hypot($0.x - point.x, $0.y - point.y)) }
            .filter { $0.1 <= endpointSnapDistance }
            .min { $0.1 < $1.1 }
            .map(\.0)
    }

    private func updateDraftWallEnd(_ raw: CGPoint) {
        guard let start = draftWallStart else { return }

        // Endpoint snap wins over angle snap — connecting beats alignment.
        if let snapped = snapToEndpoint(raw) {
            draftWallEnd = snapped
            snapIndicator = snapped
            return
        }

        var end = raw
        if angleSnapEnabled {
            let dx = raw.x - start.x
            let dy = raw.y - start.y
            let length = hypot(dx, dy)
            if length > 4 {
                let angle = atan2(dy, dx) * 180 / .pi
                let snappedAngle = (angle / 45).rounded() * 45
                if abs(angle - snappedAngle) <= angleSnapThreshold {
                    let radians = snappedAngle * .pi / 180
                    end = CGPoint(
                        x: start.x + cos(radians) * length,
                        y: start.y + sin(radians) * length
                    )
                }
            }
        }
        draftWallEnd = end
        snapIndicator = nil
    }

    private func finishWallDrag(translation: CGSize, tapLocation: CGPoint) {
        defer {
            draftWallStart = nil
            draftWallEnd = nil
            snapIndicator = nil
        }

        // A near-zero drag is a tap: select the nearest segment instead.
        let dragDistance = hypot(translation.width, translation.height)
        if dragDistance < 5 {
            selectedSegmentID = segments
                .map { ($0.id, $0.closest(to: tapLocation).distance) }
                .filter { $0.1 <= 14 }
                .min { $0.1 < $1.1 }
                .map(\.0)
            return
        }

        guard let start = draftWallStart, let end = draftWallEnd,
              hypot(end.x - start.x, end.y - start.y) >= 8 else { return }
        pushUndo()
        let segment = SketchSegment(start: start, end: end)
        segments.append(segment)
        selectedSegmentID = nil
    }

    private func appendCrackPoint(_ point: CGPoint) {
        if let last = draftCrackPoints.last {
            guard hypot(point.x - last.x, point.y - last.y) >= 3 else { return }
        }
        draftCrackPoints.append(point)
    }

    private func finishCrackDrag() {
        defer { draftCrackPoints = [] }
        guard draftCrackPoints.count >= 2 else { return }
        let length = zip(draftCrackPoints, draftCrackPoints.dropFirst())
            .reduce(CGFloat.zero) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
        guard length >= 10 else { return }
        pushUndo()
        cracks.append(SketchCrack(points: draftCrackPoints))
    }

    private func finishEraseDrag() {
        defer { eraserPoints = [] }
        guard !eraserPoints.isEmpty else { return }
        pushUndo()

        // Rectangles the eraser touched become 4 wall segments first, so the
        // eraser can then carve sides out of them like any other segment.
        var workingSegments = segments
        var remainingAnnotations: [SketchAnnotation] = []
        for annotation in annotations {
            if annotation.kind == .rectangle,
               SketchEraser.pathTouchesRectangle(eraserPoints, rectangle: annotation) {
                workingSegments.append(contentsOf: SketchEraser.rectangleSides(of: annotation))
            } else {
                remainingAnnotations.append(annotation)
            }
        }

        let erasedSegments = SketchEraser.erase(segments: workingSegments, along: eraserPoints)
        let erasedCracks = SketchEraser.erase(cracks: cracks, along: eraserPoints)

        // Nothing changed → don't burn an undo step.
        if erasedSegments == segments && erasedCracks == cracks && remainingAnnotations.count == annotations.count {
            undoStack.removeLast()
            return
        }

        annotations = remainingAnnotations
        segments = erasedSegments
        cracks = erasedCracks
        if let selected = selectedSegmentID, !segments.contains(where: { $0.id == selected }) {
            selectedSegmentID = nil
        }
    }

    private func deleteSelectedSegment() {
        guard let id = selectedSegmentID else { return }
        pushUndo()
        segments.removeAll { $0.id == id }
        selectedSegmentID = nil
    }

    // MARK: - Undo

    private func pushUndo() {
        undoStack.append(VectorState(
            ink: draftInk,
            annotations: annotations,
            segments: segments,
            cracks: cracks
        ))
        // Keep the stack bounded; 30 steps is plenty for a sketch session.
        if undoStack.count > 30 {
            undoStack.removeFirst()
        }
    }

    private func popUndo() {
        guard let state = undoStack.popLast() else { return }
        draftInk = state.ink
        annotations = state.annotations
        segments = state.segments
        cracks = state.cracks
        selectedID = nil
        selectedSegmentID = nil
    }

    /// Size the sketch actually needs: the furthest ink stroke or annotation in each
    /// direction plus breathing room to keep drawing. Recomputed as content changes
    /// (stroke ends, annotations move), so the canvas grows when the rep works near
    /// an edge.
    private var requiredCanvasSize: CGSize {
        var maxX: CGFloat = 0
        var maxY: CGFloat = 0
        #if canImport(PencilKit) && os(iOS)
        if let data = draftInk, !data.isEmpty,
           let drawing = try? PKDrawing(data: data), !drawing.bounds.isEmpty {
            maxX = max(maxX, drawing.bounds.maxX)
            maxY = max(maxY, drawing.bounds.maxY)
        }
        #endif
        for annotation in annotations {
            maxX = max(maxX, annotation.frame.maxX)
            maxY = max(maxY, annotation.frame.maxY)
        }
        for segment in segments {
            maxX = max(maxX, segment.boundingBox.maxX)
            maxY = max(maxY, segment.boundingBox.maxY)
        }
        for crack in cracks {
            maxX = max(maxX, crack.boundingBox.maxX)
            maxY = max(maxY, crack.boundingBox.maxY)
        }
        return CGSize(width: maxX + 160, height: maxY + 160)
    }

    // MARK: - Actions

    private func addShape(kind: SketchAnnotation.Kind) {
        let size: CGSize = {
            switch kind {
            case .rectangle: return CGSize(width: 140, height: 90)
            case .circle:    return CGSize(width: 120, height: 120)
            case .line:      return CGSize(width: 160, height: 20)
            case .arrow:     return CGSize(width: 160, height: 30)
            case .text:      return CGSize(width: 160, height: 40)
            case .pier:      return CGSize(width: 40, height: 90)
            case .sumpPump:  return CGSize(width: 60, height: 60)
            case .egressWindow: return CGSize(width: 100, height: 80)
            case .carbonStrap:  return CGSize(width: 34, height: 110)
            case .stairs:       return CGSize(width: 70, height: 110)
            case .powerBrace:   return CGSize(width: 44, height: 100)
            }
        }()
        // Cascade new shapes slightly so they don't stack on top of each other.
        let step = 20.0
        let offset = CGFloat(annotations.count % 6) * step
        let origin = CGPoint(x: 60 + offset, y: 60 + offset)
        let annotation = SketchAnnotation(kind: kind, origin: origin, size: size)
        pushUndo()
        annotations.append(annotation)
        selectedID = annotation.id
    }

    /// Handles both "add a new note" and "edit an existing note", depending on
    /// whether `editingNoteID` is set.
    private func commitNote() {
        let trimmed = pendingNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        defer {
            pendingNoteText = ""
            editingNoteID = nil
        }
        guard !trimmed.isEmpty else { return }

        if let editingID = editingNoteID,
           let index = annotations.firstIndex(where: { $0.id == editingID }) {
            annotations[index].text = trimmed
            selectedID = editingID
            return
        }

        let offset = CGFloat(annotations.count % 6) * 20
        let annotation = SketchAnnotation(
            kind: .text,
            origin: CGPoint(x: 60 + offset, y: 60 + offset),
            size: CGSize(width: 180, height: 40),
            text: trimmed
        )
        annotations.append(annotation)
        selectedID = annotation.id
    }

    /// Opens the note alert pre-filled with an existing note's text for editing.
    private func beginEditingNote(_ id: UUID) {
        guard let annotation = annotations.first(where: { $0.id == id }),
              annotation.kind == .text else { return }
        editingNoteID = id
        pendingNoteText = annotation.text
        showingNoteEntry = true
    }

    private func delete(_ id: UUID) {
        pushUndo()
        annotations.removeAll { $0.id == id }
        if selectedID == id { selectedID = nil }
    }

    /// How far each arrow-key press moves the selected annotation, in canvas points.
    private var nudgeStep: CGFloat { 4 }

    /// Nudges the selected annotation by the given delta. Clamped so it can't be
    /// pushed off the top/left of the canvas. Returns whether anything moved, so the
    /// key press can be reported as handled only when there's a selection.
    @discardableResult
    private func nudge(dx: CGFloat, dy: CGFloat) -> Bool {
        guard let id = selectedID,
              let index = annotations.firstIndex(where: { $0.id == id }) else { return false }
        var origin = annotations[index].origin
        origin.x = max(0, origin.x + dx)
        origin.y = max(0, origin.y + dy)
        annotations[index].origin = origin
        return true
    }

    /// Long-press duplication: copy the annotation, offset it ~20pt down-right, and select the copy.
    private func duplicate(_ id: UUID) {
        guard let original = annotations.first(where: { $0.id == id }) else { return }
        var copy = original
        copy.id = UUID()
        copy.origin = CGPoint(x: original.origin.x + 20, y: original.origin.y + 20)
        annotations.append(copy)
        selectedID = copy.id
        // Light haptic so the rep knows the duplication fired.
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }

    private func save() {
        proposal.sketchData = draftInk
        proposal.sketchAnnotationsData = SketchAnnotationsCodec.encode(annotations)
        proposal.sketchSegmentsData = SketchGeometryCodec.encodeSegments(segments)
        proposal.sketchCracksData = SketchGeometryCodec.encodeCracks(cracks)
        proposal.updatedAt = Date()
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Draggable / resizable annotation view

private struct AnnotationView: View {
    @Binding var annotation: SketchAnnotation
    let isSelected: Bool
    let boundsSize: CGSize
    /// Current pinch-zoom of the canvas. Global-space drag translations are divided
    /// by this so a shape tracks the finger 1:1 regardless of zoom.
    var zoomScale: CGFloat = 1
    var onSelect: () -> Void
    var onDelete: () -> Void
    var onDuplicate: () -> Void
    var onEdit: () -> Void

    @State private var dragStartOrigin: CGPoint?
    @State private var resizeStartSize: CGSize?

    private let handleSize: CGFloat = 22
    private let minSize: CGFloat = 30

    var body: some View {
        ZStack {
            // Shape wrapper — rotates with the annotation.
            ZStack(alignment: .topLeading) {
                AnnotationShape(annotation: annotation, interactive: true)
                    .frame(width: annotation.size.width, height: annotation.size.height)
                    .contentShape(Rectangle())
                    .overlay(selectionOutline)
                    .gesture(dragGesture)
                    // Double-tap a text note to edit its wording. Registered before
                    // the single-tap so SwiftUI resolves the two-tap case first.
                    .onTapGesture(count: 2) {
                        if annotation.kind == .text { onEdit() }
                    }
                    .onTapGesture { onSelect() }
                    .onLongPressGesture(minimumDuration: 0.5) {
                        onDuplicate()
                    }

                if isSelected {
                    // Delete — top-right
                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: handleSize))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.red)
                    }
                    .buttonStyle(.plain)
                    .offset(x: annotation.size.width - handleSize / 2, y: -handleSize / 2)

                    // Rotate 90° — top-left
                    rotate90Handle
                        .offset(x: -handleSize / 2, y: -handleSize / 2)

                    // Duplicate — bottom-left
                    duplicateHandle
                        .offset(x: -handleSize / 2, y: annotation.size.height - handleSize / 2)

                    // Dashed/solid toggle — bottom-center, only for line & arrow tools
                    if annotation.kind == .line || annotation.kind == .arrow {
                        dashHandle
                            .offset(
                                x: annotation.size.width / 2 - handleSize / 2,
                                y: annotation.size.height - handleSize / 2
                            )
                    }

                    if annotation.kind != .text {
                        resizeHandle
                            .offset(
                                x: annotation.size.width - handleSize / 2,
                                y: annotation.size.height - handleSize / 2
                            )
                    } else {
                        // Text notes can't be resized, but they can be re-worded.
                        editHandle
                            .offset(
                                x: annotation.size.width - handleSize / 2,
                                y: annotation.size.height - handleSize / 2
                            )
                    }
                }
            }
            .rotationEffect(.degrees(annotation.rotationDegrees))
        }
        .frame(width: annotation.size.width, height: annotation.size.height)
        .position(
            x: annotation.origin.x + annotation.size.width / 2,
            y: annotation.origin.y + annotation.size.height / 2
        )
    }

    /// Tap to rotate the annotation in fixed 90° steps (0 → 90 → 180 → 270 → 0).
    private var rotate90Handle: some View {
        Button {
            annotation.rotationDegrees = (annotation.rotationDegrees + 90)
                .truncatingRemainder(dividingBy: 360)
            onSelect()
        } label: {
            Circle()
                .fill(Color.ecoNavy)
                .frame(width: handleSize, height: handleSize)
                .overlay(
                    Image(systemName: "rotate.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                )
        }
        .buttonStyle(.plain)
    }

    private var duplicateHandle: some View {
        Button(action: onDuplicate) {
            Circle()
                .fill(Color.ecoNavy)
                .frame(width: handleSize, height: handleSize)
                .overlay(
                    Image(systemName: "plus.square.on.square")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                )
        }
        .buttonStyle(.plain)
    }

    /// Toggles the selected line/arrow between solid and dashed. The handle turns
    /// green while dashed so the current style is visible at a glance.
    private var dashHandle: some View {
        Button {
            annotation.isDashed.toggle()
            onSelect()
        } label: {
            Circle()
                .fill(annotation.isDashed ? Color.ecoGreen : Color.ecoNavy)
                .frame(width: handleSize, height: handleSize)
                .overlay(
                    Image(systemName: "square.dashed")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                )
        }
        .buttonStyle(.plain)
    }

    private var selectionOutline: some View {
        Rectangle()
            .strokeBorder(
                isSelected ? Color.ecoGreen : .clear,
                style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
            )
            .padding(-3)
    }

    private var resizeHandle: some View {
        Circle()
            .fill(Color.ecoGreen)
            .frame(width: handleSize, height: handleSize)
            .overlay(
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            )
            .contentShape(Rectangle())
            .gesture(resizeGesture)
    }

    private var editHandle: some View {
        Button(action: onEdit) {
            Circle()
                .fill(Color.ecoGreen)
                .frame(width: handleSize, height: handleSize)
                .overlay(
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                )
        }
        .buttonStyle(.plain)
    }

    private var dragGesture: some Gesture {
        // Global coordinate space so a rotated shape still drags in the
        // direction the user swipes, not the shape's local rotated axis.
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                if dragStartOrigin == nil {
                    dragStartOrigin = annotation.origin
                    onSelect()
                }
                guard let start = dragStartOrigin else { return }
                var newOrigin = CGPoint(
                    x: start.x + value.translation.width / zoomScale,
                    y: start.y + value.translation.height / zoomScale
                )
                let maxX = max(0, boundsSize.width - annotation.size.width)
                let maxY = max(0, boundsSize.height - annotation.size.height)
                newOrigin.x = min(max(0, newOrigin.x), maxX)
                newOrigin.y = min(max(0, newOrigin.y), maxY)
                annotation.origin = newOrigin
            }
            .onEnded { _ in
                dragStartOrigin = nil
            }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if resizeStartSize == nil {
                    resizeStartSize = annotation.size
                    onSelect()
                }
                guard let start = resizeStartSize else { return }
                let newWidth = max(minSize, start.width + value.translation.width)
                let newHeight = max(minSize, start.height + value.translation.height)
                annotation.size = CGSize(width: newWidth, height: newHeight)
            }
            .onEnded { _ in
                resizeStartSize = nil
            }
    }
}

private extension SketchAnnotation.Kind {
    var buttonTitle: String {
        switch self {
        case .rectangle: return "Rect"
        case .circle:    return "Oval"
        case .line:      return "Line"
        case .arrow:     return "Arrow"
        case .text:      return "Note"
        case .pier:      return "Pier"
        case .sumpPump:  return "Pump"
        case .egressWindow: return "Egress"
        case .carbonStrap:  return "Strap"
        case .stairs:       return "Stairs"
        case .powerBrace:   return "Brace"
        }
    }
}
