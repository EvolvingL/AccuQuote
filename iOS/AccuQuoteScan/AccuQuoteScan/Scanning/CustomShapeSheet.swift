import SwiftUI

// Vertices are shown in metres based on a configurable scale.

struct CustomShapeSheet: View {
    @ObservedObject var coordinator: ScanCoordinator
    let parentDismiss: DismissAction
    @Environment(\.dismiss) var dismiss

    // Canvas vertices in canvas-point coordinates
    @State private var vertices: [CGPoint] = []
    @State private var dragIndex: Int? = nil
    @State private var heightText: String = "2.4"
    @State private var canvasSize: CGSize = .zero
    @FocusState private var heightFocused: Bool

    // metres per canvas point — 1 canvas point = metersPerPoint metres
    // We use a 10m × 10m room space mapped to the canvas
    let metersPerPoint: Double = 10.0 / 300.0   // 300pt canvas = 10m

    var height: Double {
        // Double("nan")/Double("inf") parse to non-nil non-finite values, so a plain
        // `?? 2.4` wouldn't catch them — guard isFinite and a realistic range so a
        // bad height can't flow as NaN/Inf into area math, the UI, or a saved quote.
        guard let v = Double(heightText.replacingOccurrences(of: ",", with: ".")),
              v.isFinite, v > 0, v <= 100 else { return 2.4 }
        return v
    }
    var canSubmit: Bool { vertices.count >= 3 }

    // Vertex positions in metres
    var verticesInMetres: [CGPoint] {
        vertices.map { CGPoint(x: Double($0.x) * metersPerPoint,
                               y: Double($0.y) * metersPerPoint) }
    }

    // Wall segments for label display
    func wallLength(_ i: Int) -> Double {
        let a = verticesInMetres[i]
        let b = verticesInMetres[(i + 1) % vertices.count]
        let dx = Double(a.x - b.x), dy = Double(a.y - b.y)
        return sqrt(dx*dx + dy*dy)
    }

    func midpoint(_ i: Int) -> CGPoint {
        let a = vertices[i], b = vertices[(i + 1) % vertices.count]
        return CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // Instructions
                VStack(spacing: 4) {
                    Text("Draw Your Room Shape")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(AQ.ink)
                    Text("Tap the canvas to add corners. Drag a point to reposition it. Tap a point to remove it.")
                        .font(AQ.body(13))
                        .foregroundColor(AQ.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.top, 28)
                .padding(.bottom, 16)

                // Scale legend
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(AQ.blue)
                        .frame(width: 30, height: 2)
                    Text("= 1 m")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AQ.secondary)
                    Spacer()
                    if vertices.count >= 3 {
                        let area = polygonArea(verticesInMetres)
                        Text(String(format: "Area: %.1f m²", area))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AQ.green)
                    }
                    if vertices.count < 3 {
                        Text("Add at least 3 corners")
                            .font(.system(size: 12))
                            .foregroundColor(AQ.secondary.opacity(0.7))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)

                // ── Drawing canvas ────────────────────────────────────────────
                GeometryReader { geo in
                    ZStack {
                        // Background grid
                        CanvasGrid(size: geo.size, metersPerPoint: metersPerPoint)

                        // Polygon fill
                        if vertices.count >= 3 {
                            PolygonShape(points: vertices)
                                .fill(AQ.blue.opacity(0.07))
                            PolygonShape(points: vertices)
                                .stroke(AQ.blue, lineWidth: 2)
                        } else if vertices.count == 2 {
                            Path { p in
                                p.move(to: vertices[0])
                                p.addLine(to: vertices[1])
                            }
                            .stroke(AQ.blue, lineWidth: 2)
                        }

                        // Closing line (last → first) hint
                        if vertices.count >= 3 {
                            Path { p in
                                p.move(to: vertices.last!)
                                p.addLine(to: vertices.first!)
                            }
                            .stroke(AQ.blue.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        }

                        // Wall length labels
                        if vertices.count >= 2 {
                            ForEach(0..<vertices.count, id: \.self) { i in
                                if i < vertices.count - 1 || vertices.count >= 3 {
                                    let mp = midpoint(i)
                                    let len = wallLength(i)
                                    Text(String(format: "%.1fm", len))
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(AQ.blue)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(Color.white.opacity(0.85))
                                        .cornerRadius(4)
                                        .position(mp)
                                }
                            }
                        }

                        // Vertex dots
                        ForEach(0..<vertices.count, id: \.self) { i in
                            Circle()
                                .fill(dragIndex == i ? AQ.amber : AQ.blue)
                                .frame(width: dragIndex == i ? 20 : 14,
                                       height: dragIndex == i ? 20 : 14)
                                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                                .shadow(radius: 2)
                                .position(vertices[i])
                                // Tap to remove
                                .onTapGesture {
                                    vertices.remove(at: i)
                                }
                        }

                        // Vertex index labels
                        ForEach(0..<vertices.count, id: \.self) { i in
                            Text("\(i + 1)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .position(vertices[i])
                        }
                    }
                    .background(AQ.fill)
                    .cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(AQ.rule, lineWidth: 1))
                    .contentShape(Rectangle())
                    // ── Tap to add vertex ────────────────────────────────────
                    .onTapGesture { location in
                        // If near an existing vertex, don't add (tap handled by vertex layer)
                        let hitRadius: CGFloat = 18
                        let nearExisting = vertices.contains { v in
                            hypot(v.x - location.x, v.y - location.y) < hitRadius
                        }
                        if !nearExisting {
                            vertices.append(location)
                        }
                    }
                    // ── Drag to reposition vertex ────────────────────────────
                    .gesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { value in
                                if dragIndex == nil {
                                    // Find nearest vertex within 24pt
                                    let loc = value.startLocation
                                    dragIndex = vertices.indices.min {
                                        hypot(vertices[$0].x - loc.x, vertices[$0].y - loc.y) <
                                        hypot(vertices[$1].x - loc.x, vertices[$1].y - loc.y)
                                    }.flatMap { i in
                                        hypot(vertices[i].x - loc.x, vertices[i].y - loc.y) < 24 ? i : nil
                                    }
                                }
                                if let i = dragIndex {
                                    let clamped = CGPoint(
                                        x: max(8, min(geo.size.width - 8, value.location.x)),
                                        y: max(8, min(geo.size.height - 8, value.location.y))
                                    )
                                    vertices[i] = clamped
                                }
                            }
                            .onEnded { _ in dragIndex = nil }
                    )
                }
                .padding(.horizontal, 16)
                .frame(height: 300)

                // Quick shape presets
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ShapePresetButton(label: "L-shape") {
                            vertices = lShapePreset()
                        }
                        ShapePresetButton(label: "T-shape") {
                            vertices = tShapePreset()
                        }
                        ShapePresetButton(label: "Pentagon") {
                            vertices = regularPolygon(sides: 5, in: CGSize(width: 280, height: 280))
                        }
                        ShapePresetButton(label: "Hexagon") {
                            vertices = regularPolygon(sides: 6, in: CGSize(width: 280, height: 280))
                        }
                        ShapePresetButton(label: "Clear") {
                            vertices = []
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 12)

                // Height input
                HStack {
                    Text("Ceiling height")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AQ.secondary)
                    Spacer()
                    TextField("2.4", text: $heightText)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(AQ.ink)
                        .keyboardType(.decimalPad)
                        .focused($heightFocused)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                    Text("m")
                        .font(.system(size: 15))
                        .foregroundColor(AQ.secondary)
                        .padding(.leading, 4)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 12).stroke(AQ.rule, lineWidth: 1))
                .padding(.horizontal, 16)

                Spacer()

                // CTA
                VStack(spacing: 0) {
                    Divider().background(AQ.rule).padding(.bottom, 16)
                    Button {
                        coordinator.submitCustomShape(
                            vertices: verticesInMetres,
                            scale: 1.0,
                            height: height
                        )
                        dismiss()
                        parentDismiss()
                    } label: {
                        Text("Use This Shape")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 17)
                            .background(canSubmit ? AQ.blue : AQ.blue.opacity(0.35))
                            .cornerRadius(14)
                    }
                    .disabled(!canSubmit)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 36)
                }
            }
            .background(Color.white)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Back") { dismiss() }
                        .foregroundColor(AQ.secondary)
                }
            }
            .onTapGesture { heightFocused = false }
        }
    }

    // MARK: - Geometry helpers

    func polygonArea(_ pts: [CGPoint]) -> Double {
        let n = pts.count
        var sum: Double = 0
        for i in 0..<n {
            let j = (i + 1) % n
            sum += Double(pts[i].x) * Double(pts[j].y)
            sum -= Double(pts[j].x) * Double(pts[i].y)
        }
        return abs(sum) / 2.0
    }

    func regularPolygon(sides: Int, in size: CGSize) -> [CGPoint] {
        let cx = size.width / 2, cy = size.height / 2
        let r = min(cx, cy) * 0.75
        return (0..<sides).map { i in
            let angle = Double(i) * 2 * .pi / Double(sides) - .pi / 2
            return CGPoint(x: cx + r * cos(angle), y: cy + r * sin(angle))
        }
    }

    func lShapePreset() -> [CGPoint] {
        // L-shape fitted in ~280×280 canvas area
        let s: CGFloat = 140
        return [
            CGPoint(x: 50, y: 50),
            CGPoint(x: 50 + s, y: 50),
            CGPoint(x: 50 + s, y: 50 + s * 0.5),
            CGPoint(x: 50 + s * 0.5, y: 50 + s * 0.5),
            CGPoint(x: 50 + s * 0.5, y: 50 + s),
            CGPoint(x: 50, y: 50 + s),
        ]
    }

    func tShapePreset() -> [CGPoint] {
        let s: CGFloat = 130
        return [
            CGPoint(x: 50, y: 50),
            CGPoint(x: 50 + s, y: 50),
            CGPoint(x: 50 + s, y: 50 + s * 0.4),
            CGPoint(x: 50 + s * 0.7, y: 50 + s * 0.4),
            CGPoint(x: 50 + s * 0.7, y: 50 + s),
            CGPoint(x: 50 + s * 0.3, y: 50 + s),
            CGPoint(x: 50 + s * 0.3, y: 50 + s * 0.4),
            CGPoint(x: 50, y: 50 + s * 0.4),
        ]
    }
}

// MARK: - Supporting shapes for CustomShapeSheet

struct PolygonShape: Shape {
    let points: [CGPoint]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard points.count >= 2 else { return p }
        p.move(to: points[0])
        points.dropFirst().forEach { p.addLine(to: $0) }
        p.closeSubpath()
        return p
    }
}

struct CanvasGrid: View {
    let size: CGSize
    let metersPerPoint: Double
    var body: some View {
        let step = CGFloat(1.0 / metersPerPoint)  // points per 1 metre
        Canvas { ctx, sz in
            var x: CGFloat = 0
            while x <= sz.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: sz.height))
                ctx.stroke(path, with: .color(AQ.rule.opacity(0.6)), lineWidth: 0.5)
                x += step
            }
            var y: CGFloat = 0
            while y <= sz.height {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: sz.width, y: y))
                ctx.stroke(path, with: .color(AQ.rule.opacity(0.6)), lineWidth: 0.5)
                y += step
            }
        }
    }
}

struct ShapePresetButton: View {
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AQ.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(AQ.fill)
                .cornerRadius(20)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(AQ.rule, lineWidth: 1))
        }
    }
}

// MARK: - Measurement input field

struct MeasurementField: View {
    let label: String
    let hint: String
    let unit: String
    @Binding var text: String
    var focused: FocusState<ManualEntrySheet.Field?>.Binding
    let field: ManualEntrySheet.Field
    let next: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AQ.secondary)
                .frame(width: 110, alignment: .leading)
            TextField(hint, text: $text)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(AQ.ink)
                .keyboardType(.decimalPad)
                .focused(focused, equals: field)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity)
            Text(unit)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(AQ.secondary)
                .padding(.leading, 6)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(focused.wrappedValue == field ? AQ.blue : AQ.rule, lineWidth: 1)
                .animation(.easeInOut(duration: 0.15), value: focused.wrappedValue == field)
        )
    }
}

