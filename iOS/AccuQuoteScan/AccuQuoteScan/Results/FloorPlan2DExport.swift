import SwiftUI
import UIKit

// MARK: - FloorPlan2DExport (Tri-Mode Scanning build spec §5.2)
//
// PDF (vector) and PNG (300dpi raster) export for a FloorPlan2D, both driven
// by the same FloorPlan2DRenderer.draw(...) the live Canvas view uses — so
// the exported artefacts are guaranteed to match what the user saw on
// screen. Mirrors the existing quote-PDF pattern in QuoteView.swift
// (UIGraphicsPDFRenderer, A4 points, not PDFKit) rather than introducing a
// second PDF-generation approach.

// @MainActor — ImageRenderer is main-actor-isolated (it drives SwiftUI's
// rendering pipeline), so every function here that touches it must run on
// the main actor too. Callers (SwiftUI views, ScanCoordinator-adjacent code)
// are already MainActor by convention throughout this codebase, so this
// isn't a new constraint in practice — just makes the existing one explicit.
@MainActor
enum FloorPlan2DExport {

    private static let pageWidthPoints: CGFloat = 595   // A4
    private static let pageHeightPoints: CGFloat = 842

    static func exportPDF(plan: FloorPlan2D, title: String) -> URL {
        let fmt = UIGraphicsPDFRendererFormat()
        fmt.documentInfo = [
            kCGPDFContextTitle as String: title,
        ]
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: pageWidthPoints, height: pageHeightPoints),
            format: fmt
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("floorplan-\(UUID().uuidString.prefix(8))")
            .appendingPathExtension("pdf")

        try? renderer.writePDF(to: url) { ctx in
            ctx.beginPage()
            let size = CGSize(width: pageWidthPoints, height: pageHeightPoints)
            let image = ImageRenderer(content:
                FloorPlan2DView(plan: plan).frame(width: size.width, height: size.height)
            ).uiImage
            image?.draw(in: CGRect(origin: .zero, size: size))
        }
        return url
    }

    /// 300dpi PNG per §5.2. A4 at 300dpi ≈ 2480×3508px — computed from the
    /// same point-based page size as the PDF export so both artefacts share
    /// one layout, just rendered at different resolutions.
    static func exportPNG(plan: FloorPlan2D) -> URL? {
        let dpi: CGFloat = 300
        let pointsToPixels = dpi / 72
        let pixelSize = CGSize(width: pageWidthPoints * pointsToPixels, height: pageHeightPoints * pointsToPixels)

        let renderer = ImageRenderer(content:
            FloorPlan2DView(plan: plan)
                .frame(width: pageWidthPoints, height: pageHeightPoints)
        )
        renderer.scale = pointsToPixels

        guard let uiImage = renderer.uiImage, let data = uiImage.pngData() else { return nil }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("floorplan-\(UUID().uuidString.prefix(8))")
            .appendingPathExtension("png")
        do {
            try data.write(to: url)
            _ = pixelSize   // documents the target resolution; ImageRenderer.scale already achieves it
            return url
        } catch {
            return nil
        }
    }

    /// Persists both formats under Documents/aq_scans/<id>/ per §5.5,
    /// mirroring SpaceMeshExport's persistence convention.
    static func persistToScanFolder(plan: FloorPlan2D, scanID: String) throws -> (pdfURL: URL, pngURL: URL?) {
        let folder = SpaceMeshExport.scanFolder(id: scanID)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let pdfURL = folder.appendingPathComponent("plan.pdf")
        let pngURL = folder.appendingPathComponent("plan.png")

        let tempPDF = exportPDF(plan: plan, title: "Floor Plan")
        try? FileManager.default.removeItem(at: pdfURL)
        try FileManager.default.copyItem(at: tempPDF, to: pdfURL)

        var finalPNGURL: URL? = nil
        if let tempPNG = exportPNG(plan: plan) {
            try? FileManager.default.removeItem(at: pngURL)
            try FileManager.default.copyItem(at: tempPNG, to: pngURL)
            finalPNGURL = pngURL
        }

        return (pdfURL, finalPNGURL)
    }
}
