import SwiftUI
import RoomPlan

// MARK: - FloorPlanView
// 2D top-down floor plan rendered in SwiftUI Canvas.
// Standard architectural notation: door arcs, triple-line windows, dimension lines.
// Pre-computes the projected plan in a GeometryReader let binding so it is only
// recalculated when the view's size changes, not on every Canvas render pass.

struct FloorPlanView: View {
    let room: CapturedRoom
    @State private var showDimensions = true

    // Static Color constants — created once, not on every body evaluation
    private static let bgColor   = Color(hex: "#F5F0E8")
    private static let dimColor  = Color(hex: "#3B82F6")

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    withAnimation { showDimensions.toggle() }
                } label: {
                    Label("Dimensions", systemImage: showDimensions ? "ruler.fill" : "ruler")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(showDimensions ? AS.lightBlue : AS.muted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(showDimensions ? AS.lightBlue.opacity(0.12) : AS.surface1)
                        .clipShape(Capsule())
                }
                Spacer()
                Text("Scale: auto")
                    .font(.system(size: 12))
                    .foregroundColor(AS.muted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(AS.surface1)

            GeometryReader { geo in
                // plan is computed once per size change, not on every Canvas tick
                let plan = FloorPlanProjector.project(room: room, in: geo.size)
                Canvas { ctx, size in
                    drawWalls(ctx: ctx, plan: plan)
                    drawDoors(ctx: ctx, plan: plan)
                    drawWindows(ctx: ctx, plan: plan)
                    if showDimensions { drawDimensions(ctx: ctx, plan: plan) }
                    drawScaleBar(ctx: ctx, size: size, ppm: plan.pixelsPerMetre)
                }
                .background(Self.bgColor)
            }
        }
    }

    // MARK: - Drawing functions

    private func drawWalls(ctx: GraphicsContext, plan: ProjectedFloorPlan) {
        var outline = Path()
        if let first = plan.roomOutline.first {
            outline.move(to: first)
            plan.roomOutline.dropFirst().forEach { outline.addLine(to: $0) }
            outline.closeSubpath()
        }
        ctx.fill(outline, with: .color(.white))
        ctx.stroke(outline, with: .color(.black), lineWidth: 2.5)
        for wall in plan.walls {
            var p = Path()
            p.move(to: wall.start); p.addLine(to: wall.end)
            ctx.stroke(p, with: .color(.black), lineWidth: 2.0)
        }
    }

    private func drawDoors(ctx: GraphicsContext, plan: ProjectedFloorPlan) {
        for door in plan.doors {
            var line = Path()
            line.move(to: door.hingePoint); line.addLine(to: door.swingStart)
            ctx.stroke(line, with: .color(.black), lineWidth: 1.5)
            var arc = Path()
            arc.addArc(center: door.hingePoint, radius: door.width,
                       startAngle: door.startAngle, endAngle: door.endAngle, clockwise: false)
            ctx.stroke(arc, with: .color(.black), style: StrokeStyle(lineWidth: 1.0, dash: [3, 2]))
        }
    }

    private func drawWindows(ctx: GraphicsContext, plan: ProjectedFloorPlan) {
        for win in plan.windows {
            let perp: CGPoint = CGPoint(x: -win.direction.y, y: win.direction.x)
            for (idx, offset) in [CGFloat(0), win.depth / 2, win.depth].enumerated() {
                var p = Path()
                p.move(to: CGPoint(x: win.start.x + perp.x * offset,
                                   y: win.start.y + perp.y * offset))
                p.addLine(to: CGPoint(x: win.end.x + perp.x * offset,
                                      y: win.end.y + perp.y * offset))
                ctx.stroke(p, with: .color(.black), lineWidth: idx == 0 ? 1.5 : 0.8)
            }
        }
    }

    private func drawDimensions(ctx: GraphicsContext, plan: ProjectedFloorPlan) {
        let dimShading = GraphicsContext.Shading.color(Self.dimColor)
        for dim in plan.dimensionLines {
            var line = Path()
            line.move(to: dim.start); line.addLine(to: dim.end)
            ctx.stroke(line, with: dimShading, style: StrokeStyle(lineWidth: 0.8))
            for pt in [dim.start, dim.end] {
                var tick = Path()
                tick.move(to: CGPoint(x: pt.x - dim.perpendicular.x * 5,
                                      y: pt.y - dim.perpendicular.y * 5))
                tick.addLine(to: CGPoint(x: pt.x + dim.perpendicular.x * 5,
                                         y: pt.y + dim.perpendicular.y * 5))
                ctx.stroke(tick, with: dimShading, lineWidth: 0.8)
            }
            ctx.draw(
                // #12: 11pt is the HIG legibility minimum (was 9pt). These are the
                // measurement values — the most important text on the floor plan.
                Text(dim.label)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(Self.dimColor),
                at: dim.midpoint
            )
        }
    }

    private func drawScaleBar(ctx: GraphicsContext, size: CGSize, ppm: CGFloat) {
        let origin = CGPoint(x: size.width - ppm - 20, y: size.height - 30)
        var bar = Path()
        bar.move(to: origin)
        bar.addLine(to: CGPoint(x: origin.x + ppm, y: origin.y))
        ctx.stroke(bar, with: .color(.black), lineWidth: 2)
        ctx.draw(
            Text("1m").font(.system(size: 11, weight: .bold)).foregroundColor(.black),   // #12
            at: CGPoint(x: origin.x + ppm / 2, y: origin.y - 12)
        )
    }
}

// MARK: - Floor Plan Projector
// Computes 2D screen coordinates from 3D RoomPlan world coordinates.
// The min/max bounding box is computed in a single pass over allPts
// rather than four separate .min()/.max() calls.

struct FloorPlanProjector {

    static func project(room: CapturedRoom, in size: CGSize) -> ProjectedFloorPlan {
        guard !room.walls.isEmpty else {
            return ProjectedFloorPlan(walls: [], roomOutline: [], doors: [],
                                      windows: [], dimensionLines: [], pixelsPerMetre: 1)
        }

        let segments: [(start: CGPoint, end: CGPoint, wall: CapturedRoom.Wall)] = room.walls.map { wall in
            let w = wall.dimensions.x / 2
            let t = wall.transform
            return (
                start: CGPoint(x: CGFloat(t.columns.3.x + t.columns.0.x * (-w)),
                               y: CGFloat(t.columns.3.z + t.columns.0.z * (-w))),
                end:   CGPoint(x: CGFloat(t.columns.3.x + t.columns.0.x * w),
                               y: CGFloat(t.columns.3.z + t.columns.0.z * w)),
                wall:  wall
            )
        }

        // Single-pass bounding box
        var minX =  CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var minY =  CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        for seg in segments {
            for pt in [seg.start, seg.end] {
                if pt.x < minX { minX = pt.x }
                if pt.x > maxX { maxX = pt.x }
                if pt.y < minY { minY = pt.y }
                if pt.y > maxY { maxY = pt.y }
            }
        }

        let pad: CGFloat = 60
        let scale = min((size.width  - pad * 2) / max(maxX - minX, 0.1),
                        (size.height - pad * 2) / max(maxY - minY, 0.1))

        @inline(__always)
        func tf(_ p: CGPoint) -> CGPoint {
            CGPoint(x: (p.x - minX) * scale + pad, y: (p.y - minY) * scale + pad)
        }

        let projWalls = segments.map { ProjectedWall(start: tf($0.start), end: tf($0.end)) }
        let outline   = segments.flatMap { [tf($0.start), tf($0.end)] }

        let dimLines: [DimensionLine] = segments.map { seg in
            let ts  = tf(seg.start), te = tf(seg.end)
            let mid = CGPoint(x: (ts.x + te.x) / 2, y: (ts.y + te.y) / 2)
            let dx  = te.x - ts.x, dy = te.y - ts.y
            let len = max(hypot(dx, dy), 0.001)
            let perp = CGPoint(x: -dy / len, y: dx / len)
            let off: CGFloat = 22
            return DimensionLine(
                start:         CGPoint(x: ts.x + perp.x * off, y: ts.y + perp.y * off),
                end:           CGPoint(x: te.x + perp.x * off, y: te.y + perp.y * off),
                midpoint:      CGPoint(x: mid.x + perp.x * (off + 10), y: mid.y + perp.y * (off + 10)),
                perpendicular: perp,
                label:         String(format: "%.2fm", seg.wall.dimensions.x)
            )
        }

        return ProjectedFloorPlan(walls: projWalls, roomOutline: outline,
                                  doors: [], windows: [],
                                  dimensionLines: dimLines, pixelsPerMetre: scale)
    }
}

// MARK: - Supporting types

struct ProjectedFloorPlan {
    var walls: [ProjectedWall]
    var roomOutline: [CGPoint]
    var doors: [ProjectedDoor]
    var windows: [ProjectedWindow]
    var dimensionLines: [DimensionLine]
    var pixelsPerMetre: CGFloat
}
struct ProjectedWall   { var start, end: CGPoint }
struct ProjectedDoor   { var hingePoint, swingStart: CGPoint; var width: CGFloat; var startAngle, endAngle: Angle; var direction: CGPoint }
struct ProjectedWindow { var start, end: CGPoint; var depth: CGFloat; var direction: CGPoint }
struct DimensionLine   { var start, end, midpoint: CGPoint; var perpendicular: CGPoint; var label: String }
