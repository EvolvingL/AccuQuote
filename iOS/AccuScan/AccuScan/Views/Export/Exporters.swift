import Foundation
import RoomPlan
import SwiftUI
import UIKit

// MARK: - USDZExporter

enum USDZExporter {
    static func export(_ room: CapturedRoom, named name: String) async throws -> URL {
        let url = tmpURL(name: name, ext: "usdz")
        let exporter = CapturedRoom.Exporter()
        try exporter.export(room, to: url, exportOptions: [.mesh, .parametric])
        return url
    }
}

// MARK: - OBJExporter

enum OBJExporter {
    static func export(_ room: CapturedRoom, named name: String) async throws -> URL {
        // Pre-allocate: ~80 bytes per vertex line × 4 verts × wall count + header
        var obj = String()
        obj.reserveCapacity(100 + room.walls.count * 340)
        obj += "# AccuScan export\n# \(name)\n\n"
        var vertexOffset = 1
        for (i, wall) in room.walls.enumerated() {
            let w = wall.dimensions.x / 2
            let h = wall.dimensions.y / 2
            let t = wall.transform
            func vLine(_ local: SIMD4<Float>) -> String {
                let world = t * local
                return "v \(world.x) \(world.y) \(world.z)\n"
            }
            obj += "# Wall \(i + 1)\n"
            obj += vLine(SIMD4(-w, -h, 0, 1))
            obj += vLine(SIMD4( w, -h, 0, 1))
            obj += vLine(SIMD4( w,  h, 0, 1))
            obj += vLine(SIMD4(-w,  h, 0, 1))
            let o = vertexOffset
            obj += "f \(o) \(o+1) \(o+2) \(o+3)\n"
            vertexOffset += 4
        }
        let url = tmpURL(name: name, ext: "obj")
        try obj.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

// MARK: - DXFExporter

enum DXFExporter {
    static func export(_ room: CapturedRoom, named name: String) async throws -> URL {
        // Pre-allocate: ~120 bytes per LINE entity × wall count + header/footer
        var dxf = String()
        dxf.reserveCapacity(200 + room.walls.count * 130)
        dxf += "0\nSECTION\n2\nHEADER\n9\n$ACADVER\n1\nAC1015\n0\nENDSEC\n"
        dxf += "0\nSECTION\n2\nENTITIES\n"
        for wall in room.walls {
            let w  = wall.dimensions.x / 2
            let t  = wall.transform
            let x1 = t.columns.3.x + t.columns.0.x * (-w)
            let y1 = t.columns.3.z + t.columns.0.z * (-w)
            let x2 = t.columns.3.x + t.columns.0.x * w
            let y2 = t.columns.3.z + t.columns.0.z * w
            dxf += "0\nLINE\n8\n0\n10\n\(x1)\n20\n\(y1)\n30\n0.0\n11\n\(x2)\n21\n\(y2)\n31\n0.0\n"
        }
        dxf += "0\nENDSEC\n0\nEOF\n"
        let url = tmpURL(name: name, ext: "dxf")
        try dxf.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

// MARK: - CSVExporter

enum CSVExporter {
    static func export(_ room: CapturedRoom, named name: String) async throws -> URL {
        let rowCount = room.walls.count + room.doors.count + room.windows.count
        var csv = String()
        csv.reserveCapacity(60 + rowCount * 50)
        csv += "Element,Width (m),Height (m),Depth (m),Area (m²),Confidence\n"
        for (i, wall) in room.walls.enumerated() {
            let area = wall.dimensions.x * wall.dimensions.y
            csv += "Wall \(i+1),\(f(wall.dimensions.x)),\(f(wall.dimensions.y)),0.20,\(f(area)),\(conf(wall.confidence))\n"
        }
        for (i, door) in room.doors.enumerated() {
            csv += "Door \(i+1),\(f(door.dimensions.x)),\(f(door.dimensions.y)),0.10,,\(conf(door.confidence))\n"
        }
        for (i, win) in room.windows.enumerated() {
            csv += "Window \(i+1),\(f(win.dimensions.x)),\(f(win.dimensions.y)),0.10,,\(conf(win.confidence))\n"
        }
        let url = tmpURL(name: name, ext: "csv")
        try csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func f(_ v: Float) -> String { String(format: "%.3f", v) }
    private static func conf(_ c: CapturedRoom.Confidence) -> String {
        switch c {
        case .low:    return "Low"
        case .medium: return "Medium"
        case .high:   return "High"
        @unknown default: return "Unknown"
        }
    }
}

// MARK: - PDFExporter

enum PDFExporter {
    static func export(_ room: CapturedRoom, named name: String) async throws -> URL {
        let view = FloorPlanView(room: room)
            .frame(width: 595, height: 842)
            .background(Color(hex: "#F5F0E8"))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        guard let img = renderer.uiImage else { throw ExportError.renderFailed }
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let data     = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, pageRect, nil)
        UIGraphicsBeginPDFPage()
        img.draw(in: pageRect)
        UIGraphicsEndPDFContext()
        let url = tmpURL(name: name, ext: "pdf")
        try data.write(to: url)
        return url
    }
}

// MARK: - PNGExporter

enum PNGExporter {
    static func export(_ room: CapturedRoom, named name: String) async throws -> URL {
        let view = FloorPlanView(room: room)
            .frame(width: 1024, height: 1024)
            .background(Color(hex: "#F5F0E8"))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        guard let img  = renderer.uiImage,
              let data = img.pngData()
        else { throw ExportError.renderFailed }
        let url = tmpURL(name: name, ext: "png")
        try data.write(to: url)
        return url
    }
}

// MARK: - Shared helpers

private func tmpURL(name: String, ext: String) -> URL {
    // Security: sanitise the name before using it as a filename component.
    // Allow only alphanumerics, spaces, hyphens, and underscores.
    // This prevents path traversal (e.g. "../../etc/passwd") and null-byte injection.
    let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: " -_"))
    let safe = name
        .unicodeScalars
        .filter { allowed.contains($0) }
        .map { String($0) }
        .joined()
        .replacingOccurrences(of: " ", with: "_")
        .prefix(64)   // cap length — very long names can exceed filesystem limits
    let safeName = safe.isEmpty ? "scan" : String(safe)
    let ts = Int(Date().timeIntervalSince1970)
    return FileManager.default.temporaryDirectory
        .appendingPathComponent("accuscan_\(safeName)_\(ts).\(ext)")
}

enum ExportError: LocalizedError {
    case renderFailed
    var errorDescription: String? { "Export rendering failed" }
}
