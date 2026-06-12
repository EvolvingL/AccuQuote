import SwiftUI
import RoomPlan

// MARK: - ThumbnailGenerator
// Renders a small floor plan thumbnail for the home list scan cards.

enum ThumbnailGenerator {

    static func generate(from room: CapturedRoom, size: CGSize = CGSize(width: 80, height: 80)) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            drawFloorPlanThumbnail(room: room, in: ctx.cgContext, size: size)
        }
    }

    private static func drawFloorPlanThumbnail(room: CapturedRoom,
                                                in ctx: CGContext,
                                                size: CGSize) {
        // Background
        UIColor(red: 0.07, green: 0.08, blue: 0.12, alpha: 1).setFill()
        ctx.fill(CGRect(origin: .zero, size: size))

        guard !room.walls.isEmpty else { return }

        // Extract wall endpoints in XZ plane. Drop any wall whose geometry isn't
        // finite — a NaN/Inf point would poison the min/max bounds below (giving a
        // NaN scale) and draw garbage into the thumbnail.
        let segments: [(CGPoint, CGPoint)] = room.walls.compactMap { wall in
            let w = wall.dimensions.x / 2
            let t = wall.transform
            guard w.isFinite,
                  t.columns.3.x.isFinite, t.columns.3.z.isFinite,
                  t.columns.0.x.isFinite, t.columns.0.z.isFinite else { return nil }
            let s = CGPoint(x: CGFloat(t.columns.3.x + t.columns.0.x * (-w)),
                            y: CGFloat(t.columns.3.z + t.columns.0.z * (-w)))
            let e = CGPoint(x: CGFloat(t.columns.3.x + t.columns.0.x * w),
                            y: CGFloat(t.columns.3.z + t.columns.0.z * w))
            return (s, e)
        }
        guard !segments.isEmpty else { return }

        let allPts = segments.flatMap { [$0.0, $0.1] }
        guard let minX = allPts.map({ $0.x }).min(),
              let maxX = allPts.map({ $0.x }).max(),
              let minY = allPts.map({ $0.y }).min(),
              let maxY = allPts.map({ $0.y }).max() else { return }

        let pad: CGFloat = 8
        let rW = maxX - minX; let rH = maxY - minY
        let scaleX = (size.width  - pad * 2) / max(rW, 0.1)
        let scaleY = (size.height - pad * 2) / max(rH, 0.1)
        let scale  = min(scaleX, scaleY)

        func pt(_ p: CGPoint) -> CGPoint {
            CGPoint(x: (p.x - minX) * scale + pad,
                    y: (p.y - minY) * scale + pad)
        }

        UIColor(red: 0.49, green: 0.83, blue: 0.99, alpha: 0.9).setStroke()
        ctx.setLineWidth(1.5)

        for seg in segments {
            ctx.move(to: pt(seg.0))
            ctx.addLine(to: pt(seg.1))
            ctx.strokePath()
        }
    }
}
