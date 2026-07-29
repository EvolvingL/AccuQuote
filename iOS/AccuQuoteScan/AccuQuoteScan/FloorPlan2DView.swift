import SwiftUI

// MARK: - FloorPlan2DView (Tri-Mode Scanning build spec §5.2)
//
// SwiftUI Canvas renderer for FloorPlan2D — architectural-grade vector
// output, not a screenshot of the 3D view flattened. Draws walls, door
// swings, windows, dimension strings, room labels, and fixture symbols per
// §5.2's rendering rules. The plan's own coordinate space (metres, top-down,
// FloorPlan2D's header comment) is mapped to view space by a single scale +
// offset computed from the plan's bounding box, so the same drawing code
// works at any Canvas size — including the fixed page size used by
// FloorPlan2DExport's PDF/PNG renderers.

struct FloorPlan2DView: View {
    let plan: FloorPlan2D
    var showDisclaimer: Bool = true

    var body: some View {
        Canvas { context, size in
            FloorPlan2DRenderer.draw(plan: plan, in: &context, size: size, showDisclaimer: showDisclaimer)
        }
        .background(Color.white)
    }
}

// MARK: - Renderer (shared by the live Canvas view and PDF/PNG export)

enum FloorPlan2DRenderer {

    private static let inkColor = AQ.ink
    private static let secondaryColor = AQ.secondary
    private static let blueColor = AQ.blue
    private static let wallLineWidth: CGFloat = 2.5
    private static let doorArcLineWidth: CGFloat = 0.75
    private static let margin: CGFloat = 40

    /// Computes a metres→points transform that fits the plan's bounding box
    /// into `size` with `margin` padding, flipping Y since plan-space Y grows
    /// "away from the viewer" but Canvas/UIKit Y grows downward — without the
    /// flip the plan would render mirrored top-to-bottom.
    static func fitTransform(plan: FloorPlan2D, size: CGSize) -> (scale: CGFloat, offset: CGPoint) {
        let points = plan.walls.flatMap { [$0.start, $0.end] }
        guard !points.isEmpty else { return (1, .zero) }
        let xs = points.map { CGFloat($0.x) }, ys = points.map { CGFloat($0.y) }
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return (1, .zero) }

        let planWidth = max(maxX - minX, 0.1)
        let planHeight = max(maxY - minY, 0.1)
        let availableW = size.width - margin * 2
        let availableH = size.height - margin * 2
        let scale = min(availableW / planWidth, availableH / planHeight)

        // Centre the scaled plan within the available area.
        let offsetX = margin + (availableW - planWidth * scale) / 2 - minX * scale
        let offsetY = margin + (availableH - planHeight * scale) / 2 - minY * scale
        return (scale, CGPoint(x: offsetX, y: offsetY))
    }

    /// Plan-space (metres, Y "away from viewer") → view-space (points, Y down).
    static func project(_ point: SIMD2<Float>, scale: CGFloat, offset: CGPoint, size: CGSize) -> CGPoint {
        let x = CGFloat(point.x) * scale + offset.x
        let y = size.height - (CGFloat(point.y) * scale + offset.y)
        return CGPoint(x: x, y: y)
    }

    static func draw(plan: FloorPlan2D, in context: inout GraphicsContext, size: CGSize, showDisclaimer: Bool) {
        let (scale, offset) = fitTransform(plan: plan, size: size)
        func pt(_ p: SIMD2<Float>) -> CGPoint { project(p, scale: scale, offset: offset, size: size) }

        drawWalls(plan.walls, scale: scale, offset: offset, size: size, in: &context)
        drawWindows(plan.windows, project: pt, in: &context)
        drawDoors(plan.doors, project: pt, in: &context)
        drawSymbols(plan.symbols, scale: scale, offset: offset, size: size, in: &context)
        drawDimensionStrings(plan.dimensionStrings, project: pt, in: &context)
        drawRoomLabels(plan.roomLabels, project: pt, in: &context)

        if let north = plan.northAngleRadians {
            drawNorthArrow(angleRadians: north, in: &context, size: size)
        }
        drawScaleBar(metres: plan.scaleBarMetres, scale: scale, in: &context, size: size)
        if showDisclaimer {
            drawDisclaimer(in: &context, size: size)
        }
    }

    // MARK: Walls — 2.5pt near-black double-line stroke; estimated thickness
    // gets a hairline dashed inner line (§5.2).

    private static func drawWalls(_ walls: [PlanWall], scale: CGFloat, offset: CGPoint, size: CGSize, in context: inout GraphicsContext) {
        for wall in walls {
            let start = project(wall.start, scale: scale, offset: offset, size: size)
            let end = project(wall.end, scale: scale, offset: offset, size: size)

            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(path, with: .color(inkColor), style: StrokeStyle(lineWidth: wallLineWidth, lineCap: .square))

            if wall.isEstimatedThickness {
                // Hairline dashed inner line, offset perpendicular to the
                // wall by half the (estimated) thickness — flags to the
                // reader that this thickness wasn't measured, only assumed.
                let dx = end.x - start.x, dy = end.y - start.y
                let length = max(sqrt(dx * dx + dy * dy), 0.001)
                let nx = -dy / length, ny = dx / length
                let inset = CGFloat(wall.thicknessMetres) * scale / 2
                let innerStart = CGPoint(x: start.x + nx * inset, y: start.y + ny * inset)
                let innerEnd = CGPoint(x: end.x + nx * inset, y: end.y + ny * inset)
                var innerPath = Path()
                innerPath.move(to: innerStart)
                innerPath.addLine(to: innerEnd)
                context.stroke(innerPath, with: .color(secondaryColor),
                                style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
            }
        }
    }

    // MARK: Doors — opening gap + quarter-circle swing arc

    private static func drawDoors(_ doors: [PlanDoor], project: (SIMD2<Float>) -> CGPoint, in context: inout GraphicsContext) {
        for door in doors {
            let hinge = project(door.hingePoint)
            let openEnd = project(door.openEndPoint)
            let radius = hypot(openEnd.x - hinge.x, openEnd.y - hinge.y)
            let startAngle = Angle(radians: atan2(openEnd.y - hinge.y, openEnd.x - hinge.x))

            var arcPath = Path()
            arcPath.addArc(center: hinge, radius: radius,
                            startAngle: startAngle,
                            endAngle: startAngle + Angle(radians: Double(door.swingRadians)),
                            clockwise: false)
            context.stroke(arcPath, with: .color(secondaryColor), style: StrokeStyle(lineWidth: doorArcLineWidth))

            var leafPath = Path()
            leafPath.move(to: hinge)
            leafPath.addLine(to: openEnd)
            context.stroke(leafPath, with: .color(secondaryColor), style: StrokeStyle(lineWidth: doorArcLineWidth))
        }
    }

    // MARK: Windows — triple parallel line across the opening

    private static func drawWindows(_ windows: [PlanWindow], project: (SIMD2<Float>) -> CGPoint, in context: inout GraphicsContext) {
        for window in windows {
            let start = project(window.start)
            let end = project(window.end)
            let dx = end.x - start.x, dy = end.y - start.y
            let length = max(hypot(dx, dy), 0.001)
            let nx = -dy / length, ny = dx / length
            let gap: CGFloat = 2.5

            for offset in [-gap, 0, gap] {
                var path = Path()
                path.move(to: CGPoint(x: start.x + nx * offset, y: start.y + ny * offset))
                path.addLine(to: CGPoint(x: end.x + nx * offset, y: end.y + ny * offset))
                context.stroke(path, with: .color(blueColor), style: StrokeStyle(lineWidth: 1))
            }
        }
    }

    // MARK: Dimension strings — extension + dimension lines with ticks

    private static func drawDimensionStrings(_ strings: [PlanDimensionString], project: (SIMD2<Float>) -> CGPoint, in context: inout GraphicsContext) {
        for dim in strings {
            let start = project(dim.start)
            let end = project(dim.end)

            var line = Path()
            line.move(to: start)
            line.addLine(to: end)
            context.stroke(line, with: .color(blueColor), style: StrokeStyle(lineWidth: 0.75))

            // Ticks at each end, perpendicular to the dimension line.
            let dx = end.x - start.x, dy = end.y - start.y
            let length = max(hypot(dx, dy), 0.001)
            let nx = -dy / length, ny = dx / length
            let tickLen: CGFloat = 4
            for p in [start, end] {
                var tick = Path()
                tick.move(to: CGPoint(x: p.x - nx * tickLen, y: p.y - ny * tickLen))
                tick.addLine(to: CGPoint(x: p.x + nx * tickLen, y: p.y + ny * tickLen))
                context.stroke(tick, with: .color(blueColor), style: StrokeStyle(lineWidth: 0.75))
            }

            let midpoint = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
            let label = String(format: "%.2fm", dim.valueMetres)
            context.draw(
                Text(label).font(AQ.mono(9)).foregroundColor(blueColor),
                at: CGPoint(x: midpoint.x + nx * 10, y: midpoint.y + ny * 10)
            )
        }
    }

    // MARK: Room labels — name + floor area centred in the region

    private static func drawRoomLabels(_ labels: [PlanRoomLabel], project: (SIMD2<Float>) -> CGPoint, in context: inout GraphicsContext) {
        for label in labels {
            let centre = project(label.centre)
            context.draw(
                Text(label.name).font(AQ.title(13)).foregroundColor(inkColor),
                at: CGPoint(x: centre.x, y: centre.y - 8)
            )
            context.draw(
                Text(String(format: "%.1f m²", label.floorAreaSqMetres)).font(AQ.caption(11)).foregroundColor(secondaryColor),
                at: CGPoint(x: centre.x, y: centre.y + 8)
            )
        }
    }

    // MARK: Fixture symbols — standardised shape, labelled-rectangle fallback

    private static func drawSymbols(_ symbols: [PlanSymbol], scale: CGFloat, offset: CGPoint, size: CGSize, in context: inout GraphicsContext) {
        for symbol in symbols {
            let centre = project(symbol.position, scale: scale, offset: offset, size: size)
            let w = CGFloat(symbol.widthMetres) * scale
            let d = CGFloat(symbol.depthMetres) * scale

            context.drawLayer { layer in
                layer.translateBy(x: centre.x, y: centre.y)
                layer.rotate(by: Angle(radians: -Double(symbol.rotationRadians)))
                let rect = CGRect(x: -w / 2, y: -d / 2, width: w, height: d)
                let path = Path(roundedRect: rect, cornerRadius: 2)
                layer.stroke(path, with: .color(secondaryColor), style: StrokeStyle(lineWidth: 1))
                layer.draw(
                    Text(symbol.categoryLabel).font(.system(size: 7, weight: .medium)).foregroundColor(secondaryColor),
                    at: .zero
                )
            }
        }
    }

    // MARK: North arrow, scale bar, disclaimer

    private static func drawNorthArrow(angleRadians: Float, in context: inout GraphicsContext, size: CGSize) {
        let origin = CGPoint(x: size.width - 32, y: 32)
        context.drawLayer { layer in
            layer.translateBy(x: origin.x, y: origin.y)
            layer.rotate(by: Angle(radians: Double(angleRadians)))
            var arrow = Path()
            arrow.move(to: CGPoint(x: 0, y: -12))
            arrow.addLine(to: CGPoint(x: 5, y: 8))
            arrow.addLine(to: CGPoint(x: 0, y: 3))
            arrow.addLine(to: CGPoint(x: -5, y: 8))
            arrow.closeSubpath()
            layer.fill(arrow, with: .color(inkColor))
            layer.draw(Text("N").font(.system(size: 9, weight: .bold)).foregroundColor(inkColor),
                       at: CGPoint(x: 0, y: -18))
        }
    }

    private static func drawScaleBar(metres: Float, scale: CGFloat, in context: inout GraphicsContext, size: CGSize) {
        let barLengthMetres: Float = metres > 0 ? metres : 1.0
        let barWidth = CGFloat(barLengthMetres) * scale
        let origin = CGPoint(x: margin, y: size.height - 24)

        var bar = Path()
        bar.move(to: origin)
        bar.addLine(to: CGPoint(x: origin.x + barWidth, y: origin.y))
        context.stroke(bar, with: .color(inkColor), style: StrokeStyle(lineWidth: 1.5))
        for x in [origin.x, origin.x + barWidth] {
            var tick = Path()
            tick.move(to: CGPoint(x: x, y: origin.y - 3))
            tick.addLine(to: CGPoint(x: x, y: origin.y + 3))
            context.stroke(tick, with: .color(inkColor), style: StrokeStyle(lineWidth: 1.5))
        }
        context.draw(
            Text(String(format: "%.0fm", barLengthMetres)).font(.system(size: 9)).foregroundColor(secondaryColor),
            at: CGPoint(x: origin.x + barWidth / 2, y: origin.y - 10)
        )
    }

    private static func drawDisclaimer(in context: inout GraphicsContext, size: CGSize) {
        context.draw(
            Text("Not to scale — indicative").font(.system(size: 8)).foregroundColor(secondaryColor.opacity(0.7)),
            at: CGPoint(x: size.width / 2, y: size.height - 8)
        )
    }
}
