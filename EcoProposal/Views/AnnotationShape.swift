import SwiftUI

/// Renders a single sketch annotation (shape or text note) at its stored frame.
/// Used both in the interactive editor and the printable PDF layer.
struct AnnotationShape: View {
    let annotation: SketchAnnotation
    var interactive: Bool = false

    var body: some View {
        switch annotation.kind {
        case .rectangle:
            Rectangle()
                .stroke(strokeColor, lineWidth: 1.5)
                .frame(width: annotation.size.width, height: annotation.size.height)
        case .circle:
            Ellipse()
                .stroke(strokeColor, lineWidth: 1.5)
                .frame(width: annotation.size.width, height: annotation.size.height)
        case .line:
            DoubleArrowShape()
                .stroke(strokeColor, style: strokeStyle())
                .frame(width: annotation.size.width, height: annotation.size.height)
        case .arrow:
            ArrowShape()
                .stroke(strokeColor, style: strokeStyle())
                .frame(width: annotation.size.width, height: annotation.size.height)
        case .text:
            Text(annotation.text.isEmpty ? "note" : annotation.text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(strokeColor)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.92))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(strokeColor.opacity(0.6), lineWidth: 0.6)
                )
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: annotation.size.width, alignment: .leading)
        case .pier:
            PierShape(strokeColor: strokeColor)
                .frame(width: annotation.size.width, height: annotation.size.height)
        case .sumpPump:
            SumpPumpShape(strokeColor: strokeColor)
                .frame(width: annotation.size.width, height: annotation.size.height)
        case .egressWindow:
            EgressWindowShape(strokeColor: strokeColor)
                .frame(width: annotation.size.width, height: annotation.size.height)
        case .carbonStrap:
            CarbonStrapShape(strokeColor: strokeColor)
                .frame(width: annotation.size.width, height: annotation.size.height)
        case .stairs:
            StairsShape(strokeColor: strokeColor)
                .frame(width: annotation.size.width, height: annotation.size.height)
        case .powerBrace:
            PowerBraceShape(strokeColor: strokeColor)
                .frame(width: annotation.size.width, height: annotation.size.height)
        }
    }

    private var strokeColor: Color { Color(red: 0.13, green: 0.35, blue: 0.55) }

    /// Stroke style for the line/arrow tools, dashed when the annotation is flagged.
    private func strokeStyle() -> StrokeStyle {
        StrokeStyle(
            lineWidth: 1.5,
            lineCap: .round,
            lineJoin: .round,
            dash: annotation.isDashed ? [7, 5] : []
        )
    }
}

private struct ArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let midY = rect.midY
        let tipX = rect.maxX
        let headLength: CGFloat = min(14, rect.width * 0.25)
        let headHalfWidth: CGFloat = min(9, rect.height * 0.5)

        p.move(to: CGPoint(x: rect.minX, y: midY))
        p.addLine(to: CGPoint(x: tipX, y: midY))
        p.move(to: CGPoint(x: tipX - headLength, y: midY - headHalfWidth))
        p.addLine(to: CGPoint(x: tipX, y: midY))
        p.addLine(to: CGPoint(x: tipX - headLength, y: midY + headHalfWidth))
        return p
    }
}

/// A straight line with an arrowhead on both ends — used for the "line" tool so reps
/// can mark a span/dimension that clearly points in both directions.
private struct DoubleArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let midY = rect.midY
        let leftX = rect.minX
        let rightX = rect.maxX
        let headLength: CGFloat = min(14, rect.width * 0.25)
        let headHalfWidth: CGFloat = min(9, rect.height * 0.5)

        // Shaft
        p.move(to: CGPoint(x: leftX, y: midY))
        p.addLine(to: CGPoint(x: rightX, y: midY))

        // Right-hand arrowhead
        p.move(to: CGPoint(x: rightX - headLength, y: midY - headHalfWidth))
        p.addLine(to: CGPoint(x: rightX, y: midY))
        p.addLine(to: CGPoint(x: rightX - headLength, y: midY + headHalfWidth))

        // Left-hand arrowhead
        p.move(to: CGPoint(x: leftX + headLength, y: midY - headHalfWidth))
        p.addLine(to: CGPoint(x: leftX, y: midY))
        p.addLine(to: CGPoint(x: leftX + headLength, y: midY + headHalfWidth))
        return p
    }
}

/// Helical pier — a vertical column with helix threads at the bottom (like a screw
/// driven into the ground) plus a rectangular cap/plate on top. Reads clearly as
/// "pier" on a floor-plan sketch.
private struct PierShape: View {
    let strokeColor: Color

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let shaftWidth = max(6, w * 0.35)
            let shaftX = (w - shaftWidth) / 2
            let capHeight = max(4, h * 0.10)
            let capWidth = min(w, shaftWidth * 1.8)
            let capX = (w - capWidth) / 2
            let helixCount = 3
            let helixTop = h * 0.55
            let helixBottom = h * 0.94
            let helixSpacing = (helixBottom - helixTop) / CGFloat(helixCount)

            ZStack {
                // Cap / bearing plate
                Rectangle()
                    .stroke(strokeColor, lineWidth: 1.5)
                    .frame(width: capWidth, height: capHeight)
                    .position(x: w / 2, y: capHeight / 2 + 1)

                // Shaft
                Rectangle()
                    .stroke(strokeColor, lineWidth: 1.5)
                    .frame(width: shaftWidth, height: h - capHeight - 4)
                    .position(x: w / 2, y: capHeight + (h - capHeight) / 2)

                // Helical threads at bottom
                Path { p in
                    for i in 0..<helixCount {
                        let y = helixTop + CGFloat(i) * helixSpacing
                        // Left-to-right sloped line (thread)
                        p.move(to: CGPoint(x: shaftX - 4, y: y + helixSpacing * 0.4))
                        p.addLine(to: CGPoint(x: shaftX + shaftWidth + 4, y: y))
                    }
                }
                .stroke(strokeColor, style: StrokeStyle(lineWidth: 1.2, lineCap: .round))

                // Pointed tip
                Path { p in
                    p.move(to: CGPoint(x: shaftX, y: helixBottom))
                    p.addLine(to: CGPoint(x: w / 2, y: h - 1))
                    p.addLine(to: CGPoint(x: shaftX + shaftWidth, y: helixBottom))
                }
                .stroke(strokeColor, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

/// Basement egress window — the foundation wall with a paned window opening in it
/// and a semicircular window well bulging to the outside. Reads clearly as "egress
/// window" on a floor-plan sketch.
private struct EgressWindowShape: View {
    let strokeColor: Color

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let cx = w / 2
            let wallY = h * 0.30
            let windowHalf = w * 0.28
            let left = cx - windowHalf
            let right = cx + windowHalf
            let wellRadius = min(windowHalf * 1.25, h - wallY - 3)
            let paneThird = (right - left) / 3

            ZStack {
                // Foundation wall
                Path { p in
                    p.move(to: CGPoint(x: 3, y: wallY))
                    p.addLine(to: CGPoint(x: w - 3, y: wallY))
                }
                .stroke(strokeColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))

                // Window opening straddling the wall, with two mullions (3 panes)
                Path { p in
                    let top = wallY - h * 0.14
                    let bottom = wallY + h * 0.14
                    p.addRect(CGRect(x: left, y: top, width: right - left, height: bottom - top))
                    p.move(to: CGPoint(x: left + paneThird, y: top))
                    p.addLine(to: CGPoint(x: left + paneThird, y: bottom))
                    p.move(to: CGPoint(x: left + paneThird * 2, y: top))
                    p.addLine(to: CGPoint(x: left + paneThird * 2, y: bottom))
                }
                .stroke(strokeColor, style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))

                // Window well — semicircle bulging outward (below the wall). Sampled
                // with trig so the curve is unambiguously on the lower side.
                Path { p in
                    let steps = 28
                    for i in 0...steps {
                        let angle = Double.pi * Double(i) / Double(steps) // 0…π
                        let point = CGPoint(
                            x: cx + wellRadius * cos(angle),   // right → left
                            y: wallY + wellRadius * sin(angle) // always below the wall
                        )
                        if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
                    }
                }
                .stroke(strokeColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

                // "EG" label inside the well
                Text("EG")
                    .font(.system(size: max(8, w * 0.15), weight: .heavy, design: .rounded))
                    .foregroundStyle(strokeColor)
                    .position(x: cx, y: wallY + wellRadius * 0.55)
            }
        }
    }
}

/// Carbon fiber strap — a vertical reinforcing strap applied to a bowing block
/// wall to hold it from caving in. Drawn as a vertical band with a carbon-weave
/// crosshatch and anchor plates at the top (sill) and bottom (floor), with a "CF"
/// label so it reads clearly on a floor-plan sketch.
private struct CarbonStrapShape: View {
    let strokeColor: Color

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let strapWidth = max(10, w * 0.5)
            let strapX = (w - strapWidth) / 2
            let plateWidth = min(w - 2, strapWidth * 1.8)
            let plateX = (w - plateWidth) / 2
            let plateHeight = max(4, h * 0.06)
            let strapTop = plateHeight + 2
            let strapBottom = h - plateHeight - 2

            ZStack {
                // Strap band outline
                Path { p in
                    p.addRect(CGRect(x: strapX, y: strapTop,
                                     width: strapWidth, height: strapBottom - strapTop))
                }
                .stroke(strokeColor, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))

                // Carbon weave — crosshatch inside the band
                Path { p in
                    let spacing: CGFloat = 9
                    var y = strapTop
                    while y < strapBottom {
                        let yTop = min(y + spacing, strapBottom)
                        p.move(to: CGPoint(x: strapX, y: yTop))
                        p.addLine(to: CGPoint(x: strapX + strapWidth, y: y))
                        p.move(to: CGPoint(x: strapX, y: y))
                        p.addLine(to: CGPoint(x: strapX + strapWidth, y: yTop))
                        y += spacing
                    }
                }
                .stroke(strokeColor.opacity(0.5), style: StrokeStyle(lineWidth: 0.7))

                // Anchor plates at top and bottom
                Path { p in
                    p.addRect(CGRect(x: plateX, y: 1, width: plateWidth, height: plateHeight))
                    p.addRect(CGRect(x: plateX, y: h - plateHeight - 1,
                                     width: plateWidth, height: plateHeight))
                }
                .fill(strokeColor.opacity(0.15))
                Path { p in
                    p.addRect(CGRect(x: plateX, y: 1, width: plateWidth, height: plateHeight))
                    p.addRect(CGRect(x: plateX, y: h - plateHeight - 1,
                                     width: plateWidth, height: plateHeight))
                }
                .stroke(strokeColor, style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))

                // "CF" label running up the strap
                Text("CF")
                    .font(.system(size: max(8, strapWidth * 0.42), weight: .heavy, design: .rounded))
                    .foregroundStyle(strokeColor)
                    .rotationEffect(.degrees(-90))
                    .position(x: w / 2, y: h / 2)
            }
        }
    }
}

/// Basement stairway — plan-view architectural convention: an outlined run divided
/// into evenly-spaced treads with a direction arrow along the travel path. Rotate in
/// 90° steps to orient it to the actual stairway.
private struct StairsShape: View {
    let strokeColor: Color

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let inset: CGFloat = 1
            let stepCount = 8

            ZStack {
                // Outer run + tread lines
                Path { p in
                    p.addRect(CGRect(x: inset, y: inset, width: w - inset * 2, height: h - inset * 2))
                    let usableH = h - inset * 2
                    for i in 1..<stepCount {
                        let y = inset + usableH * CGFloat(i) / CGFloat(stepCount)
                        p.move(to: CGPoint(x: inset, y: y))
                        p.addLine(to: CGPoint(x: w - inset, y: y))
                    }
                }
                .stroke(strokeColor, style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))

                // Direction arrow up the center of the run
                Path { p in
                    let cx = w / 2
                    let top = h * 0.14
                    let bottom = h * 0.86
                    let headLen = min(12, h * 0.14)
                    let headHalf = min(7, w * 0.18)
                    p.move(to: CGPoint(x: cx, y: bottom))
                    p.addLine(to: CGPoint(x: cx, y: top))
                    p.move(to: CGPoint(x: cx - headHalf, y: top + headLen))
                    p.addLine(to: CGPoint(x: cx, y: top))
                    p.addLine(to: CGPoint(x: cx + headHalf, y: top + headLen))
                }
                .stroke(strokeColor, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

/// Power brace steel I-beam — a bold capital "I": wide top and bottom flanges
/// joined by a thick web, filled so it reads as structural steel at a glance.
private struct PowerBraceShape: View {
    let strokeColor: Color

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let flangeHeight = max(4, h * 0.14)
            let webWidth = max(4, w * 0.28)

            Path { p in
                // Top flange
                p.addRect(CGRect(x: 1, y: 1, width: w - 2, height: flangeHeight))
                // Bottom flange
                p.addRect(CGRect(x: 1, y: h - flangeHeight - 1, width: w - 2, height: flangeHeight))
                // Web
                p.addRect(CGRect(
                    x: (w - webWidth) / 2, y: flangeHeight + 1,
                    width: webWidth, height: h - flangeHeight * 2 - 2
                ))
            }
            .fill(strokeColor.opacity(0.22))
            .overlay(
                Path { p in
                    p.addRect(CGRect(x: 1, y: 1, width: w - 2, height: flangeHeight))
                    p.addRect(CGRect(x: 1, y: h - flangeHeight - 1, width: w - 2, height: flangeHeight))
                    p.addRect(CGRect(
                        x: (w - webWidth) / 2, y: flangeHeight + 1,
                        width: webWidth, height: h - flangeHeight * 2 - 2
                    ))
                }
                .stroke(strokeColor, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            )
        }
    }
}

/// Sump pump / sump crock — architectural convention: circle with "SP" label.
private struct SumpPumpShape: View {
    let strokeColor: Color

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                // Outer crock ring
                Circle()
                    .stroke(strokeColor, lineWidth: 1.5)
                    .frame(width: side, height: side)
                // Inner ring — represents the pump inside the crock
                Circle()
                    .stroke(strokeColor.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .frame(width: side * 0.55, height: side * 0.55)
                // "SP" label
                Text("SP")
                    .font(.system(size: max(9, side * 0.28), weight: .heavy, design: .rounded))
                    .foregroundStyle(strokeColor)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
    }
}
