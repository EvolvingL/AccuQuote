import Foundation
import ModelIO
import SceneKit
import simd

// MARK: - SpaceMeshExport (Tri-Mode Scanning build spec §3.3, §5.5)
//
// Exports the frozen capture-volume triangles as OBJ and USDZ, saved under
// Documents/aq_scans/<id>/ per §5.5's persistence convention (shared with
// Room mode's eventual ScanResult.meshURL — Space mode doesn't yet write a
// ScanResult, so this writes directly into the same folder structure ahead
// of that unification landing).
//
// Untextured "clean CAD" export only for now — §3.3's texture-baking step
// (project highest-confidence camera frame per face) needs the raw ARFrame
// captures kept alongside the mesh, which SpaceCaptureCoordinator doesn't
// retain yet (frozenTriangles has no per-triangle source-frame reference).
// The geometry export itself — the part a plumber/fitter actually needs to
// forward to a supplier or open in CAD — is real and complete.

enum SpaceMeshExportError: Error {
    case noGeometry
    case writeFailed
}

enum SpaceMeshExport {

    struct ExportedFiles {
        let objURL: URL
        let usdzURL: URL
    }

    /// Root folder per §5.5: Documents/aq_scans/<id>/
    static func scanFolder(id: String) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("aq_scans", isDirectory: true).appendingPathComponent(id, isDirectory: true)
    }

    /// Builds an MDLAsset from the captured triangles, then exports both OBJ
    /// (CAD/SketchUp, §5.3) and USDZ (AR Quick Look/iMessage, §5.3) — ModelIO
    /// can write both formats from the one in-memory mesh so there's no risk
    /// of the two files disagreeing.
    static func export(triangles: [SpaceMeshExtraction.ExtractedTriangle], scanID: String) throws -> ExportedFiles {
        guard !triangles.isEmpty else { throw SpaceMeshExportError.noGeometry }

        let folder = scanFolder(id: scanID)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let asset = try buildAsset(from: triangles)

        let objURL = folder.appendingPathComponent("model.obj")
        let usdzURL = folder.appendingPathComponent("model.usdz")

        // Remove any stale export from a previous attempt — MDLAsset.export
        // throws if the destination already exists.
        try? FileManager.default.removeItem(at: objURL)
        try? FileManager.default.removeItem(at: usdzURL)

        do {
            try asset.export(to: objURL)
            try asset.export(to: usdzURL)
        } catch {
            throw SpaceMeshExportError.writeFailed
        }

        return ExportedFiles(objURL: objURL, usdzURL: usdzURL)
    }

    private static func buildAsset(from triangles: [SpaceMeshExtraction.ExtractedTriangle]) throws -> MDLAsset {
        var vertexData: [Float] = []
        vertexData.reserveCapacity(triangles.count * 3 * 3)
        for tri in triangles {
            vertexData.append(contentsOf: [tri.v0.x, tri.v0.y, tri.v0.z])
            vertexData.append(contentsOf: [tri.v1.x, tri.v1.y, tri.v1.z])
            vertexData.append(contentsOf: [tri.v2.x, tri.v2.y, tri.v2.z])
        }
        let indices: [UInt32] = Array(0..<UInt32(triangles.count * 3))

        let allocator = MDLMeshBufferDataAllocator()
        let vertexBuffer = allocator.newBuffer(
            with: Data(bytes: vertexData, count: vertexData.count * MemoryLayout<Float>.size),
            type: .vertex
        )
        let indexBuffer = allocator.newBuffer(
            with: Data(bytes: indices, count: indices.count * MemoryLayout<UInt32>.size),
            type: .index
        )

        let submesh = MDLSubmesh(
            indexBuffer: indexBuffer,
            indexCount: indices.count,
            indexType: .uInt32,
            geometryType: .triangles,
            material: MDLMaterial(name: "clean-cad", scatteringFunction: MDLScatteringFunction())
        )

        let vertexDescriptor = MDLVertexDescriptor()
        vertexDescriptor.attributes[0] = MDLVertexAttribute(
            name: MDLVertexAttributePosition, format: .float3, offset: 0, bufferIndex: 0
        )
        vertexDescriptor.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<Float>.size * 3)

        let mesh = MDLMesh(
            vertexBuffer: vertexBuffer, vertexCount: triangles.count * 3,
            descriptor: vertexDescriptor, submeshes: [submesh]
        )
        mesh.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: 0.5)

        let asset = MDLAsset()
        asset.add(mesh)
        return asset
    }
}
