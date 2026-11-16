import SwiftUI

/// Wraps any content in a grid-paper frame with compass labels around the outside:
/// BACK on top, FRONT on bottom, LEFT on the left, RIGHT on the right.
/// Used by the sketch editor, the sketch thumbnail, and the printable sketch page.
struct CompassGridFrame<Content: View>: View {
    var labelFontSize: CGFloat = 14
    var labelColor: Color = Color(red: 0.35, green: 0.35, blue: 0.35)
    var gridSpacing: CGFloat = GridPaperBackground.oneFoot   // 18pt = 1 ft at 1/4"=1' scale
    var showsScaleLegend: Bool = true
    var content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            let insetTop = labelFontSize + 6
            let insetBottom = labelFontSize + 6
            let insetSide = labelFontSize + 6

            ZStack {
                // Top / bottom labels
                VStack {
                    Text("BACK")
                        .compassLabelStyle(size: labelFontSize, color: labelColor)
                        .frame(maxWidth: .infinity)
                    Spacer()
                    Text("FRONT")
                        .compassLabelStyle(size: labelFontSize, color: labelColor)
                        .frame(maxWidth: .infinity)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)

                // Left / right labels (rotated 90° so they read vertically)
                HStack {
                    Text("LEFT")
                        .compassLabelStyle(size: labelFontSize, color: labelColor)
                        .rotationEffect(.degrees(-90))
                        .fixedSize()
                        .frame(width: insetSide)
                    Spacer()
                    Text("RIGHT")
                        .compassLabelStyle(size: labelFontSize, color: labelColor)
                        .rotationEffect(.degrees(90))
                        .fixedSize()
                        .frame(width: insetSide)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)

                // Grid + content inside the inset
                ZStack {
                    GridPaperBackground(spacing: gridSpacing)
                    content()

                    if showsScaleLegend {
                        scaleLegend
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .padding(6)
                    }
                }
                .padding(EdgeInsets(top: insetTop, leading: insetSide, bottom: insetBottom, trailing: insetSide))
            }
        }
    }

    /// Small legend in the bottom-right that shows the drafting scale + a 1-ft
    /// reference bar (one grid square wide).
    private var scaleLegend: some View {
        HStack(spacing: 6) {
            HStack(spacing: 0) {
                Rectangle().fill(Color.black.opacity(0.55)).frame(width: gridSpacing, height: 6)
                Rectangle().fill(Color.white).frame(width: gridSpacing, height: 6)
            }
            .overlay(
                Rectangle().stroke(Color.black.opacity(0.55), lineWidth: 0.5)
            )
            Text("1 ft")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.7))
            Text("• Scale 1/4\" = 1'")
                .font(.system(size: 8))
                .foregroundStyle(Color.black.opacity(0.55))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(red: 0.98, green: 0.97, blue: 0.92).opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.black.opacity(0.25), lineWidth: 0.5)
        )
    }
}

private extension View {
    func compassLabelStyle(size: CGFloat, color: Color) -> some View {
        self.font(.system(size: size, weight: .heavy))
            .tracking(2)
            .foregroundStyle(color)
    }
}

#Preview {
    CompassGridFrame {
        Color.clear
    }
    .frame(width: 500, height: 500)
    .padding()
}
