import SwiftUI

// MARK: - CoverageRingView
//
// Face-ID-style segmented ring showing room scan coverage.
// 24 arc segments arranged clockwise from 12 o'clock.
// Identical to AccuQuote's CoverageRingView for design consistency.

struct CoverageRingView: View {

    let sectors:    [SectorState]   // 24 elements
    let coverage:   Float           // 0–1
    let isComplete: Bool

    private static let segmentCount = 24
    private static let gapDeg: Double   = 4
    private static let ringSize: CGFloat = 140
    private static let lineWidth: CGFloat = 8

    private var pct: Int { Int(coverage * 100) }
    private var litCount: Int { Int((coverage * Float(Self.segmentCount)).rounded()) }

    private func segmentColour(index: Int) -> Color {
        if isComplete { return Color(red: 0.13, green: 0.72, blue: 0.43) }
        if index < litCount { return AS.lightBlue }
        return Color.white.opacity(0.10)
    }

    private var numberColour: Color {
        if isComplete       { return Color(red: 0.13, green: 0.72, blue: 0.43) }
        if coverage >= 0.20 { return AS.lightBlue }
        return .white
    }

    var body: some View {
        ZStack {
            ForEach(0..<Self.segmentCount, id: \.self) { i in
                SegmentArc(
                    index:     i,
                    total:     Self.segmentCount,
                    gapDeg:    Self.gapDeg,
                    lineWidth: Self.lineWidth,
                    size:      Self.ringSize
                )
                .stroke(segmentColour(index: i),
                        style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                .animation(.easeInOut(duration: 0.3), value: litCount)
            }

            VStack(spacing: 1) {
                Text("\(pct)%")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundColor(numberColour)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.3), value: pct)
                if isComplete {
                    Text("Complete")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(red: 0.13, green: 0.72, blue: 0.43))
                } else {
                    Text("scanned")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .frame(width: Self.ringSize, height: Self.ringSize)
    }
}

// MARK: - SegmentArc shape

private struct SegmentArc: Shape {
    let index:     Int
    let total:     Int
    let gapDeg:    Double
    let lineWidth: CGFloat
    let size:      CGFloat

    func path(in rect: CGRect) -> Path {
        let centre   = CGPoint(x: rect.midX, y: rect.midY)
        let radius   = (size / 2) - lineWidth / 2
        let span     = 360.0 / Double(total)
        let start    = span * Double(index) - 90
        let arcStart = start + gapDeg / 2
        let arcEnd   = start + span   - gapDeg / 2

        var p = Path()
        p.addArc(center: centre, radius: radius,
                 startAngle: .degrees(arcStart),
                 endAngle:   .degrees(arcEnd),
                 clockwise:  false)
        return p
    }
}
