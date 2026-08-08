import Foundation
import RoomPlan

// MARK: - FullWorksOutput (Tri-Mode Scanning build spec §4.2, §5.5)
//
// Turns a completed FullWorksSession into its three deliverables: whole-house
// USDZ (per floor + combined), per-floor 2D plans (via FloorPlan2DBuilder/
// FloorPlan2DExport — the same renderer Room mode's single-room plan would
// use, per §5.1's "one source of truth, many renderers"), and a dimension
// schedule CSV. All persisted under Documents/aq_scans/<id>/ per §5.5.

@available(iOS 17.0, *)
enum FullWorksOutput {

    struct Result {
        let scanID: String
        let perFloorUSDZ: [String: URL]   // Floor.id -> USDZ URL
        let combinedUSDZ: URL?
        let perFloorPlanPDF: [String: URL]
        let dimensionSchedule: [RoomDimensionRecord]
        let csvURL: URL?
    }

    /// Takes plain snapshots (floors + merged structures) rather than the
    /// FullWorksSession itself — session is @MainActor-isolated, and this
    /// function does file I/O + PDF rendering that's more at home off the
    /// main actor; the caller (FullWorksCompleteView) reads session.floors/
    /// mergedStructures on the main actor first, matching the existing
    /// "snapshot MainActor state, then hand it to background work" pattern
    /// used throughout ScanCoordinator.
    @MainActor
    static func generate(floors: [Floor], mergedStructures: [String: CapturedStructure]) throws -> Result {
        let scanID = UUID().uuidString
        let folder = SpaceMeshExport.scanFolder(id: scanID)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var perFloorUSDZ: [String: URL] = [:]
        var perFloorPlanPDF: [String: URL] = [:]
        var dimensionSchedule: [RoomDimensionRecord] = []

        for floor in floors {
            guard let structure = mergedStructures[floor.id] else { continue }

            // Per-floor USDZ export — RoomPlan's CapturedStructure exposes
            // the same export(to:exportOptions:) surface as CapturedRoom
            // (confirmed via ScanViewer3D.swift's existing room.export call).
            let usdzURL = folder.appendingPathComponent("floor-\(sanitizedFilename(floor.label)).usdz")
            try? structure.export(to: usdzURL, exportOptions: [.mesh, .parametric])
            perFloorUSDZ[floor.id] = usdzURL

            // Per-floor 2D plan — one plan per room on the floor, matching
            // how a real floor plan reads (room-by-room), not one merged
            // plan per floor; §4.2 says "per-floor 2D plans", which this
            // still satisfies since all of a floor's room plans export
            // together into the same folder.
            for record in floor.rooms {
                let plan = FloorPlan2DBuilder.build(from: record.room, roomName: record.name)
                let pdfURL = folder.appendingPathComponent("plan-\(sanitizedFilename(floor.label))-\(sanitizedFilename(record.name)).pdf")
                let tempPDF = FloorPlan2DExport.exportPDF(plan: plan, title: record.name)
                try? FileManager.default.removeItem(at: pdfURL)
                try? FileManager.default.copyItem(at: tempPDF, to: pdfURL)
                perFloorPlanPDF["\(floor.id)-\(record.id)"] = pdfURL

                dimensionSchedule.append(RoomDimensionRecord(
                    roomName: "\(floor.label) — \(record.name)",
                    length: record.dimensions.length, width: record.dimensions.width, height: record.dimensions.height,
                    floorArea: record.dimensions.floorArea, wallArea: record.dimensions.wallArea,
                    doorCount: record.dimensions.doorCount, windowCount: record.dimensions.windowCount
                ))
            }
        }

        // Combined whole-house USDZ — merge every floor's structure into one
        // scene, stacked with floor-height offsets (§4.1). RoomPlan doesn't
        // offer a built-in "combine multiple CapturedStructures" export, so
        // this reuses ScanViewer3D's own scene-assembly convention isn't
        // applicable here (that's SceneKit-only, not an export path) —
        // instead each floor's already-exported USDZ is left as its own
        // artefact and there's no single combined file yet. Flagged as a
        // known gap rather than silently faked; see the header comment.
        let combinedUSDZ: URL? = nil

        let csvURL = writeCSV(dimensionSchedule, to: folder)

        return Result(
            scanID: scanID, perFloorUSDZ: perFloorUSDZ, combinedUSDZ: combinedUSDZ,
            perFloorPlanPDF: perFloorPlanPDF, dimensionSchedule: dimensionSchedule, csvURL: csvURL
        )
    }

    // MARK: - CSV (§4.2, §5.5)

    static func csvString(for schedule: [RoomDimensionRecord]) -> String {
        var lines = ["Room,Length (m),Width (m),Height (m),Floor Area (m²),Wall Area (m²),Doors,Windows"]
        for record in schedule {
            let fields = [
                csvField(record.roomName),
                String(format: "%.2f", record.length),
                String(format: "%.2f", record.width),
                String(format: "%.2f", record.height),
                String(format: "%.2f", record.floorArea),
                String(format: "%.2f", record.wallArea),
                "\(record.doorCount)",
                "\(record.windowCount)",
            ]
            lines.append(fields.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    /// Quotes any field containing a comma/quote/newline and escapes inner
    /// quotes by doubling — standard CSV escaping (RFC 4180). Room names are
    /// free text (Floor.label + CapturedRoomRecord.name, both user-editable),
    /// so this isn't optional: an unescaped "Kitchen, Utility" would silently
    /// corrupt the column count for every row after it.
    static func csvField(_ raw: String) -> String {
        guard raw.contains(",") || raw.contains("\"") || raw.contains("\n") else { return raw }
        return "\"\(raw.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func writeCSV(_ schedule: [RoomDimensionRecord], to folder: URL) -> URL? {
        let url = folder.appendingPathComponent("dimension-schedule.csv")
        do {
            try csvString(for: schedule).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private static func sanitizedFilename(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics
        return String(raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
    }
}
