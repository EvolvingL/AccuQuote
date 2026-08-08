import SwiftUI

// MARK: - CoverageRingView
//
// Face-ID-style segmented ring showing room scan coverage.
// 24 arc segments arranged clockwise from the top (12 o'clock = sector 0).
//
// Segments light up proportionally to the coverage percentage:
//  • Segments up to the coverage threshold → bright blue (lit)
//  • Segments beyond the threshold         → dark, barely visible
//  • All complete                           → green
//
// Percentage in the centre.

struct CoverageRingView: View {

    let sectors:     [SectorState]  // 24 elements
    let coverage:    Float          // 0–1
    let isComplete:  Bool

    private static let segmentCount = 24
    private static let gapDeg: Double = 4
    private static let ringSize: CGFloat = 140
    private static let lineWidth: CGFloat = 8

    private var pct: Int { Int(coverage * 100) }

    // How many segments should be lit based on coverage
    private var litCount: Int {
        Int((coverage * Float(Self.segmentCount)).rounded())
    }

    // Colour for a segment by index
    private func segmentColour(index: Int) -> Color {
        if isComplete { return Color(red: 0.13, green: 0.72, blue: 0.43) }  // green
        if index < litCount {
            // Lit: bright blue matching the app icon blue
            return Color(red: 0.00, green: 0.48, blue: 1.00)
        }
        return Color.white.opacity(0.10)   // unvisited
    }

    // Ring colour tint for percentage number
    private var numberColour: Color {
        if isComplete        { return Color(red: 0.13, green: 0.72, blue: 0.43) }
        if coverage >= 0.20  { return Color(red: 0.00, green: 0.48, blue: 1.00) }
        return .white
    }

    var body: some View {
        ZStack {
            // Segments
            ForEach(0..<Self.segmentCount, id: \.self) { i in
                SegmentArc(
                    index:        i,
                    total:        Self.segmentCount,
                    gapDeg:       Self.gapDeg,
                    lineWidth:    Self.lineWidth,
                    size:         Self.ringSize
                )
                .stroke(
                    segmentColour(index: i),
                    style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round)
                )
                .animation(.easeInOut(duration: 0.3), value: litCount)
            }

            // Centre label
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

// MARK: - Individual segment arc shape

private struct SegmentArc: Shape {
    let index:     Int
    let total:     Int
    let gapDeg:    Double
    let lineWidth: CGFloat
    let size:      CGFloat

    func path(in rect: CGRect) -> Path {
        let centre  = CGPoint(x: rect.midX, y: rect.midY)
        let radius  = (size / 2) - lineWidth / 2
        let span    = 360.0 / Double(total)
        let start   = span * Double(index) - 90    // -90 = start at top (12 o'clock)
        let arcStart = start + gapDeg / 2
        let arcEnd   = start + span - gapDeg / 2

        var p = Path()
        p.addArc(center:     centre,
                 radius:     radius,
                 startAngle: .degrees(arcStart),
                 endAngle:   .degrees(arcEnd),
                 clockwise:  false)
        return p
    }
}

// MARK: - Preview

#if DEBUG
struct CoverageRingView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CoverageRingView(
                sectors: (0..<24).map { i in
                    SectorState(azimuthHit: i < 12, verticallySwept: i < 6)
                },
                coverage: 0.48,
                isComplete: false
            )
        }
    }
}
#endif
