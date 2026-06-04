import RealityKit
import ARKit

// MARK: - AROverlayCoordinator
// Manages WallHighlightEntity lifecycle in a RealityKit scene.
//
// Integration note: RoomCaptureView hosts its own internal ARView which is not
// directly accessible. To use RealityKit overlays on top of RoomCaptureView,
// a transparent ARView must be layered over RoomCaptureView in the same
// UIViewController, sharing the same ARSession via ARView(frame:, cameraMode: .nonAR)
// or by using ARView.session = roomCaptureSession.arSession.
//
// Until that wiring is implemented, wall highlight entities are managed via
// the RoomCaptureView's own scene graph (RoomCaptureView renders its own
// RealityKit overlays for the room model). This coordinator is retained for
// when a custom ARView overlay is added.

final class AROverlayCoordinator {
    private weak var arView: ARView?
    private var highlightEntities: [UUID: WallHighlightEntity] = [:]
    private var anchorEntities:    [UUID: AnchorEntity]        = [:]

    func setARView(_ view: ARView) { self.arView = view }

    func sync(walls: [TrackedWall]) {
        guard let arView else { return }

        let activeIDs = Set(walls.map { $0.id })

        for wall in walls {
            if let existing = highlightEntities[wall.id] {
                existing.update(to: wall.highlightState, animated: true)
                existing.transform = Transform(matrix: wall.worldTransform)
            } else {
                let anchor    = AnchorEntity(world: wall.worldTransform)
                let highlight = WallHighlightEntity.make(for: wall)
                anchor.addChild(highlight)
                arView.scene.addAnchor(anchor)
                highlightEntities[wall.id] = highlight
                anchorEntities[wall.id]    = anchor
            }
        }

        for id in highlightEntities.keys where !activeIDs.contains(id) {
            anchorEntities[id]?.removeFromParent()
            highlightEntities.removeValue(forKey: id)
            anchorEntities.removeValue(forKey: id)
        }
    }

    func clearAll() {
        for anchor in anchorEntities.values { anchor.removeFromParent() }
        highlightEntities.removeAll()
        anchorEntities.removeAll()
    }
}
