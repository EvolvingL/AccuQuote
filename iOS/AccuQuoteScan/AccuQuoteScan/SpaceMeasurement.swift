import Foundation
import simd

// MARK: - SpaceMeasurement (Tri-Mode Scanning build spec §3.2, §3.3)
//
// Pure math over plain SIMD3<Float> point clouds — no ARKit types, no
// RoomPlan types, fully fixture-testable (see DevToolsChecks.space*). The
// capture-session layer (SpaceCaptureCoordinator) extracts world-space
// triangle vertices via SpaceMeshExtraction and hands the resulting point
// list to these functions; nothing here needs to know how the points were
// captured.

enum SpaceMeasurement {

    // MARK: - Oriented bounding box (§3.2 "PCA on vertices → width/height/depth")

    struct OrientedBoundingBox {
        let center: SIMD3<Float>
        let axes: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)   // unit vectors, right-handed
        let halfExtents: SIMD3<Float>                          // along axes.0/1/2 respectively

        var size: SIMD3<Float> { halfExtents * 2 }
    }

    /// Fits an oriented bounding box to a point cloud via PCA: the box's
    /// principal axes are the eigenvectors of the points' covariance matrix,
    /// so the box hugs the data's actual orientation (e.g. a void that's
    /// rotated 15° relative to world axes still gets a tight-fitting box)
    /// rather than an axis-aligned box that would over-report the extent of
    /// anything not perfectly wall-aligned.
    static func orientedBoundingBox(of points: [SIMD3<Float>]) -> OrientedBoundingBox? {
        guard points.count >= 3 else { return nil }

        let centroid = points.reduce(SIMD3<Float>.zero, +) / Float(points.count)
        let covariance = covarianceMatrix(of: points, centroid: centroid)
        guard let eigenvectors = jacobiEigenvectors(of: covariance) else { return nil }

        // Project every point onto each eigenvector to find the box's extent
        // along that axis — this is what actually determines width/height/depth,
        // the eigenvectors alone only give orientation.
        var minProj = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maxProj = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for point in points {
            let relative = point - centroid
            let p0 = simd_dot(relative, eigenvectors.0)
            let p1 = simd_dot(relative, eigenvectors.1)
            let p2 = simd_dot(relative, eigenvectors.2)
            minProj = SIMD3<Float>(min(minProj.x, p0), min(minProj.y, p1), min(minProj.z, p2))
            maxProj = SIMD3<Float>(max(maxProj.x, p0), max(maxProj.y, p1), max(maxProj.z, p2))
        }

        let halfExtents = (maxProj - minProj) / 2
        let boxLocalCenter = (minProj + maxProj) / 2
        let worldCenter = centroid
            + eigenvectors.0 * boxLocalCenter.x
            + eigenvectors.1 * boxLocalCenter.y
            + eigenvectors.2 * boxLocalCenter.z

        guard halfExtents.x.isFinite, halfExtents.y.isFinite, halfExtents.z.isFinite,
              halfExtents.x >= 0, halfExtents.y >= 0, halfExtents.z >= 0 else { return nil }

        return OrientedBoundingBox(center: worldCenter, axes: eigenvectors, halfExtents: halfExtents)
    }

    // Plain [row][col] scalar representation, not simd_float3x3 — the Jacobi
    // sweep below needs arbitrary element read/write (a[i][j] = ...), which
    // simd_float3x3 doesn't expose (its Swift overlay only bridges whole-
    // column access via `.columns.0/.1/.2`, not a 2D subscript). Using a
    // plain array sidesteps that entirely and is just as fast for a fixed
    // 3×3 case with no per-iteration allocation pressure worth optimising.
    private static func covarianceMatrix(of points: [SIMD3<Float>], centroid: SIMD3<Float>) -> [[Float]] {
        var xx: Float = 0, yy: Float = 0, zz: Float = 0
        var xy: Float = 0, xz: Float = 0, yz: Float = 0
        for point in points {
            let d = point - centroid
            xx += d.x * d.x; yy += d.y * d.y; zz += d.z * d.z
            xy += d.x * d.y; xz += d.x * d.z; yz += d.y * d.z
        }
        let n = Float(points.count)
        return [
            [xx / n, xy / n, xz / n],
            [xy / n, yy / n, yz / n],
            [xz / n, yz / n, zz / n],
        ]
    }

    /// Jacobi eigenvalue algorithm for a real symmetric 3×3 matrix — chosen
    /// over a generic linear-algebra library dependency since a 3×3
    /// symmetric case converges in a handful of sweeps and needs no external
    /// package. Returns the three eigenvectors (not sorted by eigenvalue —
    /// callers that need a canonical "longest axis first" ordering should
    /// sort by projected extent after the fact, which orientedBoundingBox
    /// does implicitly via halfExtents).
    private static func jacobiEigenvectors(of matrix: [[Float]]) -> (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)? {
        var a = matrix
        var v: [[Float]] = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]

        for _ in 0..<50 {
            // Find largest off-diagonal element
            var p = 0, q = 1
            var maxOffDiag: Float = abs(a[1][0])
            if abs(a[2][0]) > maxOffDiag { p = 0; q = 2; maxOffDiag = abs(a[2][0]) }
            if abs(a[2][1]) > maxOffDiag { p = 1; q = 2; maxOffDiag = abs(a[2][1]) }

            if maxOffDiag < 1e-9 { break }   // converged

            let app = a[p][p], aqq = a[q][q], apq = a[p][q]
            guard apq != 0 else { break }
            let theta = (aqq - app) / (2 * apq)
            let t = (theta >= 0 ? Float(1) : Float(-1)) / (abs(theta) + sqrt(theta * theta + 1))
            let c = 1 / sqrt(t * t + 1)
            let s = t * c

            // Apply Jacobi rotation to A (symmetric update) and accumulate into V
            var newA = a
            newA[p][p] = app - t * apq
            newA[q][q] = aqq + t * apq
            newA[p][q] = 0; newA[q][p] = 0
            for i in 0..<3 where i != p && i != q {
                let aip = a[i][p], aiq = a[i][q]
                newA[i][p] = c * aip - s * aiq; newA[p][i] = newA[i][p]
                newA[i][q] = s * aip + c * aiq; newA[q][i] = newA[i][q]
            }
            a = newA

            var newV = v
            for i in 0..<3 {
                let vip = v[i][p], viq = v[i][q]
                newV[i][p] = c * vip - s * viq
                newV[i][q] = s * vip + c * viq
            }
            v = newV
        }

        let e0 = SIMD3<Float>(v[0][0], v[1][0], v[2][0])
        let e1 = SIMD3<Float>(v[0][1], v[1][1], v[2][1])
        let e2 = SIMD3<Float>(v[0][2], v[1][2], v[2][2])
        guard simd_length(e0) > 0.5, simd_length(e1) > 0.5, simd_length(e2) > 0.5 else { return nil }
        return (simd_normalize(e0), simd_normalize(e1), simd_normalize(e2))
    }

    // MARK: - Tap-to-measure (§3.2)

    /// Straight-line distance between two points the user tapped on the
    /// frozen mesh (already unprojected from screen space to world space by
    /// the caller via a hit-test against the captured geometry).
    static func pointToPointDistance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        simd_distance(a, b)
    }

    // MARK: - Frame fitting (§3.2 "For window/door frames specifically…")

    struct FittedRectangle {
        let center: SIMD3<Float>
        let widthAxis: SIMD3<Float>     // unit vector, in-plane
        let heightAxis: SIMD3<Float>    // unit vector, in-plane, ⟂ widthAxis
        let planeNormal: SIMD3<Float>   // unit vector, out of plane
        let width: Float
        let height: Float

        /// The idealised rectangle's four corners, in-plane, world space —
        /// only exact if the fitted shape truly is a rectangle. Real, possibly
        /// racked frames are checked against the ACTUAL point cloud corners
        /// (see actualCorners below), not these.
        var idealCorners: [SIMD3<Float>] {
            let hw = width / 2, hh = height / 2
            return [
                center - widthAxis * hw - heightAxis * hh,
                center + widthAxis * hw - heightAxis * hh,
                center + widthAxis * hw + heightAxis * hh,
                center - widthAxis * hw + heightAxis * hh,
            ]
        }
    }

    /// Detects the dominant plane in a point cloud (the frame's face) via the
    /// smallest-variance PCA axis, projects every point onto that plane, then
    /// fits an axis-aligned (in-plane) rectangle to the projected boundary.
    /// Reuses the same PCA machinery as orientedBoundingBox — a plane's
    /// normal is just the least-significant principal axis, since the frame
    /// face has near-zero point spread along its own normal.
    static func fittedRectangle(of points: [SIMD3<Float>]) -> FittedRectangle? {
        guard points.count >= 3 else { return nil }

        let centroid = points.reduce(SIMD3<Float>.zero, +) / Float(points.count)
        let covariance = covarianceMatrix(of: points, centroid: centroid)
        guard let eigenvectors = jacobiEigenvectors(of: covariance) else { return nil }

        // Project every point onto each axis to find which has the smallest
        // extent — that's the plane normal (points barely vary along it,
        // since a frame face is nearly flat).
        func extent(along axis: SIMD3<Float>) -> Float {
            var lo: Float = .greatestFiniteMagnitude, hi: Float = -.greatestFiniteMagnitude
            for p in points {
                let d = simd_dot(p - centroid, axis)
                lo = min(lo, d); hi = max(hi, d)
            }
            return hi - lo
        }
        let axes = [eigenvectors.0, eigenvectors.1, eigenvectors.2]
        let extents = axes.map(extent(along:))
        guard let normalIndex = extents.indices.min(by: { extents[$0] < extents[$1] }) else { return nil }

        let normal = axes[normalIndex]
        let inPlaneAxes = axes.enumerated().filter { $0.offset != normalIndex }.map { $0.element }
        guard inPlaneAxes.count == 2 else { return nil }
        let widthAxis = inPlaneAxes[0]
        let heightAxis = inPlaneAxes[1]

        var minW: Float = .greatestFiniteMagnitude, maxW: Float = -.greatestFiniteMagnitude
        var minH: Float = .greatestFiniteMagnitude, maxH: Float = -.greatestFiniteMagnitude
        for p in points {
            let rel = p - centroid
            let w = simd_dot(rel, widthAxis)
            let h = simd_dot(rel, heightAxis)
            minW = min(minW, w); maxW = max(maxW, w)
            minH = min(minH, h); maxH = max(maxH, h)
        }

        let width = maxW - minW
        let height = maxH - minH
        guard width.isFinite, height.isFinite, width >= 0, height >= 0 else { return nil }

        let rectCenter = centroid
            + widthAxis * (minW + maxW) / 2
            + heightAxis * (minH + maxH) / 2

        return FittedRectangle(
            center: rectCenter, widthAxis: widthAxis, heightAxis: heightAxis,
            planeNormal: normal, width: width, height: height
        )
    }

    /// The real point cloud's four corners nearest the fitted rectangle's
    /// four ideal corners — used to measure the two ACTUAL diagonals (which
    /// differ from each other exactly when the real frame is out of square;
    /// FittedRectangle's own idealCorners always form a perfect rectangle by
    /// construction, so they can't surface racking on their own).
    ///
    /// Uses a greedy UNIQUE assignment (each real point can only be claimed by
    /// one ideal corner) rather than each ideal corner independently picking
    /// its own nearest point. Without uniqueness, a near-square point cloud
    /// (in-plane variance close to isotropic — exactly the case this
    /// function most needs to get right, since it's what a real racked-but-
    /// nearly-square frame looks like) can make PCA pick in-plane axes
    /// rotated ~45° from the frame's true edges. That flips idealCorners
    /// onto the diagonals instead of the edges, and two ideal corners then
    /// end up nearest the SAME real point — collapsing both diagonals to
    /// equal length and silently reporting "square" for an actually-racked
    /// frame. Assigning matches greedily by ascending distance (closest
    /// pairs claimed first) and removing claimed points from the pool for
    /// subsequent corners fixes this: every real point maps to at most one
    /// ideal corner, so all 4 real corners are represented and the two
    /// diagonals reflect the actual point cloud.
    static func actualCorners(of points: [SIMD3<Float>], nearestTo rectangle: FittedRectangle) -> [SIMD3<Float>] {
        let ideals = rectangle.idealCorners
        guard !points.isEmpty else { return ideals }

        // Every (idealIndex, pointIndex) candidate pair, sorted by distance —
        // greedily assign the closest pairs first, skipping any ideal or
        // point already claimed.
        struct Candidate { let idealIndex: Int; let pointIndex: Int; let distance: Float }
        var candidates: [Candidate] = []
        candidates.reserveCapacity(ideals.count * points.count)
        for (i, ideal) in ideals.enumerated() {
            for (j, point) in points.enumerated() {
                candidates.append(Candidate(idealIndex: i, pointIndex: j, distance: simd_distance(point, ideal)))
            }
        }
        candidates.sort { $0.distance < $1.distance }

        var result = ideals   // fallback: an ideal corner with no available point keeps its ideal position
        var idealClaimed = Array(repeating: false, count: ideals.count)
        var pointClaimed = Array(repeating: false, count: points.count)
        var remaining = ideals.count

        for candidate in candidates {
            guard remaining > 0 else { break }
            guard !idealClaimed[candidate.idealIndex], !pointClaimed[candidate.pointIndex] else { continue }
            idealClaimed[candidate.idealIndex] = true
            pointClaimed[candidate.pointIndex] = true
            result[candidate.idealIndex] = points[candidate.pointIndex]
            remaining -= 1
        }
        return result
    }
}

// MARK: - SpaceDimensions (§3.3 — mirrors RoomDimensions conventions)

struct SpaceDimensions: Codable {
    let width: Double
    let height: Double
    let depth: Double
    let scanMethod: ScanMethod

    var widthStr:  String { String(format: "%.2f", width) }
    var heightStr: String { String(format: "%.2f", height) }
    var depthStr:  String { String(format: "%.2f", depth) }

    /// mm-precision strings — Space mode's accuracy target (±1cm at close
    /// range per §0) is meaningfully tighter than Room mode's, and a
    /// tradesperson measuring an under-sink void wants millimetres, not
    /// metres-to-2dp ("562mm" reads as a real measurement; "0.56m" doesn't).
    var widthMM:  String { String(format: "%.0fmm", width * 1000) }
    var heightMM: String { String(format: "%.0fmm", height * 1000) }
    var depthMM:  String { String(format: "%.0fmm", depth * 1000) }

    init(width: Double, height: Double, depth: Double, scanMethod: ScanMethod) {
        self.width = width
        self.height = height
        self.depth = depth
        self.scanMethod = scanMethod
    }

    init(obb: SpaceMeasurement.OrientedBoundingBox, scanMethod: ScanMethod = .lidar) {
        // OBB axes aren't inherently ordered "width/height/depth" — sort by
        // extent so the largest horizontal-ish extent reads as width, matching
        // how a tradesperson would describe a void (widest opening first).
        let extents = [obb.size.x, obb.size.y, obb.size.z].sorted(by: >).map { Double($0) }
        self.width = extents[0]
        self.height = extents[1]
        self.depth = extents[2]
        self.scanMethod = scanMethod
    }
}

// MARK: - FrameReveal (§3.2 — window/door frame reveal width/height/depth + diagonals)

/// Output for the frame-specific measurement path: reveal width/height (the
/// fitted rectangle) plus the depth of the reveal (wall thickness at the
/// opening) and both corner-to-corner diagonals, which is how a tradesperson
/// checks a frame is actually square before ordering a replacement.
struct FrameReveal: Codable {
    let width: Double
    let height: Double
    let depth: Double
    let diagonalA: Double
    let diagonalB: Double
    let scanMethod: ScanMethod

    var widthMM:     String { String(format: "%.0fmm", width * 1000) }
    var heightMM:    String { String(format: "%.0fmm", height * 1000) }
    var depthMM:     String { String(format: "%.0fmm", depth * 1000) }
    var diagonalAMM: String { String(format: "%.0fmm", diagonalA * 1000) }
    var diagonalBMM: String { String(format: "%.0fmm", diagonalB * 1000) }

    /// Difference between the two diagonals — 0 for a perfectly square frame.
    /// Real timber/UPVC frames commonly rack a few mm; > ~5mm is worth flagging.
    var diagonalDeltaMM: Double { abs(diagonalA - diagonalB) * 1000 }
    var isSquareWithinTolerance: Bool { diagonalDeltaMM <= 5.0 }

    /// corners must be the 4 real point-cloud corners nearest the rectangle's
    /// ideal corners (see SpaceMeasurement.actualCorners), in the order
    /// FittedRectangle.idealCorners produces them: [--, +-, ++, -+] around
    /// width/height axes. Using the real corners (not the idealised
    /// rectangle's own corners, which are equal by construction) is what
    /// lets diagonalA/diagonalB actually differ and surface a racked frame.
    init(rectangle: SpaceMeasurement.FittedRectangle, corners: [SIMD3<Float>], depth: Double, scanMethod: ScanMethod = .lidar) {
        self.width = Double(rectangle.width)
        self.height = Double(rectangle.height)
        self.depth = depth
        if corners.count == 4 {
            self.diagonalA = Double(simd_distance(corners[0], corners[2]))
            self.diagonalB = Double(simd_distance(corners[1], corners[3]))
        } else {
            let fallback = Double(sqrt(rectangle.width * rectangle.width + rectangle.height * rectangle.height))
            self.diagonalA = fallback
            self.diagonalB = fallback
        }
        self.scanMethod = scanMethod
    }
}

// MARK: - SpaceQuoteAttachment (§3.3 "flows into the Claude generation context")
//
// Pure text formatting — the exact copy style the build spec calls out:
// "Replace kitchen sink unit — void measured 562 × 448 × 585 mm". No SwiftUI/
// networking here, so it's fixture-testable like the rest of this file; the
// call site (SpaceScanFlowView's onAttach) is what actually appends this into
// a job description string ahead of quote generation.
enum SpaceQuoteAttachment {
    static func note(itemLabel: String, dimensions: SpaceDimensions) -> String {
        "\(itemLabel) — void measured \(mmInt(dimensions.width)) × \(mmInt(dimensions.height)) × \(mmInt(dimensions.depth)) mm"
    }

    static func note(itemLabel: String, frame: FrameReveal) -> String {
        var note = "\(itemLabel) — frame reveal \(mmInt(frame.width)) × \(mmInt(frame.height)) mm, \(mmInt(frame.depth)) mm deep"
        if !frame.isSquareWithinTolerance {
            note += " (diagonals differ by \(Int(frame.diagonalDeltaMM.rounded()))mm — frame is out of square)"
        }
        return note
    }

    private static func mmInt(_ metres: Double) -> Int {
        Int((metres * 1000).rounded())
    }
}
