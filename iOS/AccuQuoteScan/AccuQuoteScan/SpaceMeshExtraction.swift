import Foundation
import ARKit
import simd

// MARK: - SpaceMeshExtraction (Tri-Mode Scanning build spec §3.2)
//
// Converts ARKit's raw ARMeshAnchor geometry (Metal buffers with
// framework-reported stride/offset/format — NOT a tightly-packed array,
// there's typically 4 bytes of alignment padding after each float3) into
// plain Swift arrays of world-space triangles. This is the only place in
// Space mode that touches unsafe pointers; everything downstream (OBB
// fitting, voxel coverage) works on plain SIMD3<Float> arrays and is
// ordinary, fixture-testable Swift.
//
// Reads buffer.contents() via the geometry source's own reported stride/
// offset/componentsPerVector rather than assuming MemoryLayout<SIMD3<Float>>.stride
// (16 bytes on most platforms due to SIMD alignment) matches ARKit's actual
// on-disk layout — trusting the framework's own numbers is what makes this
// correct regardless of Apple changing the internal packing in a future SDK.

enum SpaceMeshExtraction {

    struct ExtractedTriangle {
        let v0: SIMD3<Float>
        let v1: SIMD3<Float>
        let v2: SIMD3<Float>
        var centroid: SIMD3<Float> { (v0 + v1 + v2) / 3 }
    }

    /// Extracts every triangle face of a mesh anchor, in world space (applies
    /// the anchor's transform to each local-space vertex). Faces are not
    /// filtered by classification or bounding volume here — see
    /// `trianglesInsideCaptureVolume` for that.
    static func worldSpaceTriangles(of anchor: ARMeshAnchor) -> [ExtractedTriangle] {
        let geometry = anchor.geometry
        let vertexBuffer = geometry.vertices
        guard vertexBuffer.format == .float3 else {
            // Documented/expected format per Apple's own sample code; if a
            // future OS version changes this, fail closed (no triangles)
            // rather than mis-read the buffer as if it matched.
            return []
        }

        let vertexPositions = readFloat3Source(vertexBuffer)
        guard !vertexPositions.isEmpty else { return [] }

        let faceElement = geometry.faces
        guard faceElement.bytesPerIndex == 2 || faceElement.bytesPerIndex == 4,
              faceElement.indexCountPerPrimitive == 3 else { return [] }

        let indices = readFaceIndices(faceElement)
        let transform = anchor.transform

        var triangles: [ExtractedTriangle] = []
        triangles.reserveCapacity(indices.count / 3)
        var i = 0
        while i + 2 < indices.count {
            let i0 = Int(indices[i]), i1 = Int(indices[i + 1]), i2 = Int(indices[i + 2])
            guard i0 < vertexPositions.count, i1 < vertexPositions.count, i2 < vertexPositions.count else {
                i += 3
                continue
            }
            let w0 = worldPosition(vertexPositions[i0], transform: transform)
            let w1 = worldPosition(vertexPositions[i1], transform: transform)
            let w2 = worldPosition(vertexPositions[i2], transform: transform)
            triangles.append(ExtractedTriangle(v0: w0, v1: w1, v2: w2))
            i += 3
        }
        return triangles
    }

    /// Same as `worldSpaceTriangles`, but only keeps faces whose centroid
    /// falls inside the given world-space axis-aligned-in-its-own-frame
    /// capture volume — this is what keeps a Space-mode scan clean (just the
    /// under-sink void, not the whole kitchen) per §3.1.
    static func trianglesInsideCaptureVolume(of anchor: ARMeshAnchor, volume: CaptureVolume) -> [ExtractedTriangle] {
        worldSpaceTriangles(of: anchor).filter { volume.contains(worldPoint: $0.centroid) }
    }

    private static func worldPosition(_ local: SIMD3<Float>, transform: simd_float4x4) -> SIMD3<Float> {
        let world4 = transform * SIMD4<Float>(local.x, local.y, local.z, 1)
        return SIMD3<Float>(world4.x, world4.y, world4.z)
    }

    // MARK: - Raw buffer readers

    private static func readFloat3Source(_ source: ARGeometrySource) -> [SIMD3<Float>] {
        guard source.componentsPerVector == 3 else { return [] }
        var result: [SIMD3<Float>] = []
        result.reserveCapacity(source.count)
        let buffer = source.buffer
        let basePointer = buffer.contents().advanced(by: source.offset)
        for i in 0..<source.count {
            let vertexPointer = basePointer.advanced(by: i * source.stride)
            let vertex = vertexPointer.assumingMemoryBound(to: Float.self)
            result.append(SIMD3<Float>(vertex[0], vertex[1], vertex[2]))
        }
        return result
    }

    private static func readFaceIndices(_ element: ARGeometryElement) -> [UInt32] {
        var result: [UInt32] = []
        let indexCount = element.count * element.indexCountPerPrimitive
        result.reserveCapacity(indexCount)
        let basePointer = element.buffer.contents()
        if element.bytesPerIndex == 2 {
            let typed = basePointer.assumingMemoryBound(to: UInt16.self)
            for i in 0..<indexCount { result.append(UInt32(typed[i])) }
        } else {
            let typed = basePointer.assumingMemoryBound(to: UInt32.self)
            for i in 0..<indexCount { result.append(typed[i]) }
        }
        return result
    }
}

// MARK: - CaptureVolume
//
// The adjustable virtual box (§3.1, default 0.8 m³ ⇒ ~0.93m per side for a
// cube, but modelled as independent width/height/depth so the UI can offer
// non-cubic presets later) placed with a tap on the first detected plane.
// Only mesh inside this box is kept.

struct CaptureVolume: Codable {
    var center: SIMD3<Float>
    var halfExtents: SIMD3<Float>   // half-width/height/depth, box is axis-aligned in its own local frame
    var orientation: simd_quatf     // rotation applied to the box's local axes before placing in world space

    init(center: SIMD3<Float>, size: SIMD3<Float>, orientation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))) {
        self.center = center
        self.halfExtents = size / 2
        self.orientation = orientation
    }

    static let defaultSideLength: Float = 0.93   // ~0.8 m³ cube per §3.1's "default 0.8 m³"

    static func defaultCube(at center: SIMD3<Float>) -> CaptureVolume {
        CaptureVolume(center: center, size: SIMD3<Float>(repeating: defaultSideLength))
    }

    /// True if the given world-space point falls inside the (possibly
    /// rotated) box — transforms the point into the box's local frame first
    /// so the containment check is a simple axis-aligned comparison there.
    func contains(worldPoint: SIMD3<Float>) -> Bool {
        let relative = worldPoint - center
        let inverseRotation = orientation.inverse
        let local = inverseRotation.act(relative)
        return abs(local.x) <= halfExtents.x
            && abs(local.y) <= halfExtents.y
            && abs(local.z) <= halfExtents.z
    }
}

// Codable conformance for simd_quatf — not Codable by default.
extension simd_quatf: @retroactive Codable {
    enum CodingKeys: String, CodingKey { case x, y, z, w }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let x = try c.decode(Float.self, forKey: .x)
        let y = try c.decode(Float.self, forKey: .y)
        let z = try c.decode(Float.self, forKey: .z)
        let w = try c.decode(Float.self, forKey: .w)
        self.init(ix: x, iy: y, iz: z, r: w)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(vector.x, forKey: .x)
        try c.encode(vector.y, forKey: .y)
        try c.encode(vector.z, forKey: .z)
        try c.encode(vector.w, forKey: .w)
    }
}
