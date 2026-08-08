import SwiftUI

// MARK: - Manual Entry Sheet

struct ManualEntrySheet: View {
    @ObservedObject var coordinator: ScanCoordinator
    @Environment(\.dismiss) var dismiss

    @State private var lengthText = ""
    @State private var widthText  = ""
    @State private var heightText = "2.4"
    @State private var showCustomShape = false
    @FocusState private var focused: Field?

    enum Field { case length, width, height }

    var length: Double? { validDimension(lengthText) }
    var width:  Double? { validDimension(widthText)  }
    var height: Double? { validDimension(heightText) }
    var canSubmit: Bool { length != nil && width != nil && height != nil }

    // Fix #7/#8: reject 0, negative, and values > 100m — a room dimension must be positive and realistic
    private func validDimension(_ text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: ",", with: ".")
        guard let v = Double(cleaned), v > 0, v <= 100 else { return nil }
        return v
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Instruction
                VStack(spacing: 6) {
                    Text("Enter Room Measurements")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(AQ.ink)
                    Text("Use a tape measure for best accuracy.")
                        .font(AQ.body(14))
                        .foregroundColor(AQ.secondary)
                }
                .padding(.top, 32)
                .padding(.bottom, 36)

                // Diagram
                RoomDiagramView()
                    .padding(.horizontal, 48)
                    .padding(.bottom, 36)

                // Inputs
                VStack(spacing: 14) {
                    MeasurementField(
                        label: "Length",
                        hint: "e.g. 4.5",
                        unit: "m",
                        text: $lengthText,
                        focused: $focused,
                        field: .length,
                        next: { focused = .width }
                    )
                    MeasurementField(
                        label: "Width",
                        hint: "e.g. 3.2",
                        unit: "m",
                        text: $widthText,
                        focused: $focused,
                        field: .width,
                        next: { focused = .height }
                    )
                    MeasurementField(
                        label: "Ceiling height",
                        hint: "e.g. 2.4",
                        unit: "m",
                        text: $heightText,
                        focused: $focused,
                        field: .height,
                        next: { focused = nil }
                    )
                }
                .padding(.horizontal, 24)

                Spacer()

                // Fix #9: show validation hint so the user knows why the button is greyed out
                if !lengthText.isEmpty || !widthText.isEmpty {
                    let hints: [String] = [
                        (validDimension(lengthText) == nil && !lengthText.isEmpty) ? "Length must be 0.1–100m" : nil,
                        (validDimension(widthText)  == nil && !widthText.isEmpty)  ? "Width must be 0.1–100m" : nil,
                        (validDimension(heightText) == nil && !heightText.isEmpty) ? "Height must be 0.1–100m" : nil,
                    ].compactMap { $0 }
                    if !hints.isEmpty {
                        Text(hints.joined(separator: " · "))
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 4)
                    }
                }

                // CTA
                VStack(spacing: 0) {
                    Divider().background(AQ.rule).padding(.bottom, 20)
                    Button {
                        guard let l = length, let w = width, let h = height else { return }
                        coordinator.submitManual(length: l, width: w, height: h)
                        dismiss()
                    } label: {
                        Text("Calculate Quote")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 17)
                            .background(canSubmit ? AQ.blue : AQ.blue.opacity(0.35))
                            .cornerRadius(14)
                    }
                    .disabled(!canSubmit)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)

                    // Custom shape option
                    Button {
                        focused = nil
                        showCustomShape = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "pentagon")
                                .font(.system(size: 13, weight: .medium))
                            Text("Different room shape?  Draw it instead")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(AQ.secondary)
                    }
                    .padding(.bottom, 36)
                }
            }
            .background(Color.white)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(AQ.secondary)
                }
            }
            .sheet(isPresented: $showCustomShape) {
                CustomShapeSheet(coordinator: coordinator, parentDismiss: dismiss)
            }
        }
        .onTapGesture { focused = nil }
    }
}

// MARK: - Room diagram (simple top-down illustration)

struct RoomDiagramView: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                // Room outline
                Rectangle()
                    .stroke(AQ.rule, lineWidth: 1.5)
                    .frame(width: w, height: h)

                // Length arrow (horizontal)
                ArrowLine(start: CGPoint(x: 12, y: h/2),
                          end:   CGPoint(x: w - 12, y: h/2))
                    .stroke(AQ.blue, lineWidth: 1)
                Text("Length")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AQ.blue)
                    .position(x: w/2, y: h/2 - 12)

                // Width arrow (vertical)
                ArrowLine(start: CGPoint(x: w/2, y: 12),
                          end:   CGPoint(x: w/2, y: h - 12))
                    .stroke(AQ.secondary, lineWidth: 1)
                Text("Width")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AQ.secondary)
                    .position(x: w/2 + 28, y: h/2)
                    .rotationEffect(.degrees(90))
            }
        }
        .frame(height: 100)
    }
}

struct ArrowLine: Shape {
    let start: CGPoint, end: CGPoint
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: start); p.addLine(to: end)
        // Arrowhead at end
        let angle = atan2(end.y - start.y, end.x - start.x)
        let size: CGFloat = 6
        p.move(to: end)
        p.addLine(to: CGPoint(x: end.x - size * cos(angle - 0.4),
                              y: end.y - size * sin(angle - 0.4)))
        p.move(to: end)
        p.addLine(to: CGPoint(x: end.x - size * cos(angle + 0.4),
                              y: end.y - size * sin(angle + 0.4)))
        // Arrowhead at start
        let angle2 = atan2(start.y - end.y, start.x - end.x)
        p.move(to: start)
        p.addLine(to: CGPoint(x: start.x - size * cos(angle2 - 0.4),
                              y: start.y - size * sin(angle2 - 0.4)))
        p.move(to: start)
        p.addLine(to: CGPoint(x: start.x - size * cos(angle2 + 0.4),
                              y: start.y - size * sin(angle2 + 0.4)))
        return p
    }
}

// MARK: - Custom Shape Sheet
// Users draw a floor plan by tapping to add vertices. Drag to reposition.
