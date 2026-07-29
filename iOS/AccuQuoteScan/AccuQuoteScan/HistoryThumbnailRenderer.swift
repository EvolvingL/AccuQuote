import SceneKit
import UIKit

// MARK: - HistoryThumbnailRenderer (Tri-Mode Scanning build spec §7)
//
// Renders a one-off JPEG thumbnail of a saved scan's USDZ artifact via
// SCNRenderer.snapshot, cached next to the model so history rows don't need
// to load/render the full model just to show a preview. Works uniformly for
// Room and Space artifacts since both already export USDZ (ScanViewer3D's
// exportUSDZ / SpaceMeshExport) — loading the exported file rather than
// re-deriving a scene from CapturedRoom/triangles avoids a second
// scene-building code path that could drift from what the 3D viewer shows.

enum HistoryThumbnailRenderer {

    /// Renders once and writes a JPEG next to the given USDZ (same folder,
    /// "thumb.jpg" per §5.5's aq_scans/<id>/ file naming). Returns the
    /// thumbnail URL on success, nil if the USDZ can't be loaded/rendered —
    /// callers must treat that as "no thumbnail available", not an error to
    /// surface to the user (a missing preview image is not a failed save).
    static func renderThumbnail(usdzURL: URL) -> URL? {
        guard let scene = try? SCNScene(url: usdzURL, options: nil) else { return nil }

        let size = CGSize(width: 240, height: 240)
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene
        renderer.autoenablesDefaultLighting = true

        frameCamera(in: scene)

        let image = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
        guard let data = image.jpegData(compressionQuality: 0.7) else { return nil }

        let thumbURL = usdzURL.deletingLastPathComponent().appendingPathComponent("thumb.jpg")
        do {
            try data.write(to: thumbURL)
            return thumbURL
        } catch {
            return nil
        }
    }

    /// Adds a camera framed on the scene's bounding sphere — USDZ files
    /// exported by RoomPlan/SpaceMeshExport don't embed a camera, so without
    /// this SCNRenderer has nothing to render from.
    private static func frameCamera(in scene: SCNScene) {
        let (min, max) = scene.rootNode.boundingBox
        let centre = SCNVector3((min.x + max.x) / 2, (min.y + max.y) / 2, (min.z + max.z) / 2)
        let extent = SCNVector3(max.x - min.x, max.y - min.y, max.z - min.z)
        let radius = CGFloat(sqrt(extent.x * extent.x + extent.y * extent.y + extent.z * extent.z)) / 2
        let distance = Swift.max(radius * 2.2, 0.5)

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(
            centre.x + Float(distance) * 0.6,
            centre.y + Float(distance) * 0.5,
            centre.z + Float(distance) * 0.6
        )
        cameraNode.look(at: centre)
        scene.rootNode.addChildNode(cameraNode)
    }
}
