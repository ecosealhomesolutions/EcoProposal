import SwiftUI

#if canImport(PencilKit) && os(iOS)
import PencilKit

/// PKCanvasView wrapper. Renders whatever `PKDrawing` is bound to `data`
/// (encoded via `PKDrawing.dataRepresentation()`).
struct DrawingCanvas: UIViewRepresentable {
    @Binding var data: Data?
    var showsToolPicker: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .anyInput          // Apple Pencil + finger
        canvas.backgroundColor = .clear            // let the grid show through
        canvas.isOpaque = false
        canvas.tool = PKInkingTool(.pen, color: .black, width: 3)

        // Load the existing drawing BEFORE assigning the delegate so the initial
        // assignment doesn't fire `canvasViewDrawingDidChange` and clobber our state.
        if let data, !data.isEmpty, let drawing = try? PKDrawing(data: data) {
            canvas.drawing = drawing
        }
        canvas.delegate = context.coordinator

        if showsToolPicker {
            let toolPicker = context.coordinator.toolPicker
            toolPicker.setVisible(true, forFirstResponder: canvas)
            toolPicker.addObserver(canvas)
            DispatchQueue.main.async {
                canvas.becomeFirstResponder()
            }
        }

        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        // Keep the coordinator's binding fresh so callback writes hit the current @State.
        context.coordinator.parent = self
        guard !context.coordinator.updatingFromCanvas else { return }

        if let data, !data.isEmpty, let drawing = try? PKDrawing(data: data) {
            if drawing.dataRepresentation() != canvas.drawing.dataRepresentation() {
                canvas.drawing = drawing
            }
        } else if !canvas.drawing.strokes.isEmpty {
            // Binding cleared externally (e.g. Clear button set data to nil) — wipe the ink.
            canvas.drawing = PKDrawing()
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let toolPicker = PKToolPicker()
        var parent: DrawingCanvas
        var updatingFromCanvas = false

        init(parent: DrawingCanvas) {
            self.parent = parent
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            updatingFromCanvas = true
            let bytes = canvasView.drawing.dataRepresentation()
            parent.data = bytes.isEmpty ? nil : bytes
            DispatchQueue.main.async { [weak self] in
                self?.updatingFromCanvas = false
            }
        }
    }
}
#else
/// Non-iOS fallback so cross-platform builds still compile. Drawing requires PencilKit + iPad.
struct DrawingCanvas: View {
    @Binding var data: Data?
    var showsToolPicker: Bool = true

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "pencil.slash").font(.largeTitle)
            Text("Sketch editing is available on iPad.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
#endif
