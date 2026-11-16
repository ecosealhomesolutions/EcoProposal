import SwiftUI

/// Drafting-paper background — cream-tinted paper with fine blue-gray minor lines and
/// heavier major lines every 4 cells. At the default 18pt spacing, one grid square
/// represents 1 ft on the sketch (scale: 1/4" = 1 ft at 72 DPI PDF output).
struct GridPaperBackground: View {
    /// One grid cell in points. 18pt = 1/4 inch at 72 DPI = 1 ft on the sketch.
    var spacing: CGFloat = GridPaperBackground.oneFoot
    var majorEvery: Int = 4
    var minorColor: Color = Color(red: 0.60, green: 0.72, blue: 0.80)
    var majorColor: Color = Color(red: 0.32, green: 0.48, blue: 0.60)
    var paperColor: Color = Color(red: 0.98, green: 0.97, blue: 0.92)  // warm cream

    /// One grid square = 1 ft at the 1/4"-per-foot architectural scale.
    static let oneFoot: CGFloat = 18

    var body: some View {
        Canvas { context, size in
            // Paper fill.
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(paperColor))

            // Vertical lines.
            var index = 0
            var x: CGFloat = 0
            while x <= size.width {
                let isMajor = index.isMultiple(of: majorEvery)
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(
                    path,
                    with: .color(isMajor ? majorColor : minorColor.opacity(0.55)),
                    lineWidth: isMajor ? 0.7 : 0.3
                )
                x += spacing
                index += 1
            }

            // Horizontal lines.
            index = 0
            var y: CGFloat = 0
            while y <= size.height {
                let isMajor = index.isMultiple(of: majorEvery)
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(
                    path,
                    with: .color(isMajor ? majorColor : minorColor.opacity(0.55)),
                    lineWidth: isMajor ? 0.7 : 0.3
                )
                y += spacing
                index += 1
            }
        }
    }
}

#Preview {
    GridPaperBackground()
        .frame(width: 600, height: 400)
}
