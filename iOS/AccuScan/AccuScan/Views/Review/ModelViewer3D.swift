import SwiftUI
import SceneKit
import RoomPlan

// MARK: - ModelViewer3D
// Interactive 3D viewer using SceneKit — free pinch/rotate/pan.
// Scene is built once and cached in a Coordinator. Dimension node
// visibility and camera position are updated in-place without
// rebuilding geometry.

struct ModelViewer3D: View {
    let room: CapturedRoom
    @State private var showDimensions = true
    @State private var showObjects    = true
    @State private var viewMode: ViewMode = .perspective

    enum ViewMode: String, CaseIterable { case perspective = "3D", topDown = "Top", front = "Front" }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    withAnimation { showDimensions.toggle() }
                } label: {
                    Label("Dimensions", systemImage: showDimensions ? "ruler.fill" : "ruler")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(showDimensions ? AS.lightBlue : AS.muted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(showDimensions ? AS.lightBlue.opacity(0.12) : AS.surface1)
                        .clipShape(Capsule())
                }
                Spacer()
                Picker("View", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(AS.surface1)

            SceneKitView(room: room,
                         showDimensions: showDimensions,
                         showObjects: showObjects,
                         viewMode: viewMode)
        }
        .background(AS.bg)
    }
}

// MARK: - SceneKit wrapper

struct SceneKitView: UIViewRepresentable {
    let room: CapturedRoom
    let showDimensions: Bool
    let showObjects: Bool
    let viewMode: ModelViewer3D.ViewMode

    // MARK: Coordinator
    // Holds the SCNScene and named node references so updateUIView can
    // mutate them in-place instead of rebuilding the entire scene.
    final class Coordinator {
        var scene: SCNScene?
        weak var cameraNode: SCNNode?
        // Node name constants for targeted lookup
        static let dimensionTag = "dim"
        static let objectTag    = "obj"
        static let cameraTag    = "cam"
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.allowsCameraControl     = true
        v.autoenablesDefaultLighting = false
        v.backgroundColor         = UIColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1)
        v.antialiasingMode        = .multisampling4X

        // Build scene once and store in coordinator
        let scene = buildScene(showDimensions: showDimensions, showObjects: showObjects)
        context.coordinator.scene = scene
        v.scene = scene

        setupLighting(in: scene)
        let camNode = makeCamera(mode: viewMode)
        scene.rootNode.addChildNode(camNode)
        v.pointOfView = camNode
        context.coordinator.cameraNode = camNode

        return v
    }

    func updateUIView(_ v: SCNView, context: Context) {
        guard let scene = context.coordinator.scene else { return }

        // Toggle dimension label visibility in-place — no geometry rebuild
        scene.rootNode.childNodes(passingTest: { n, _ in n.name == Coordinator.dimensionTag })
            .forEach { $0.isHidden = !showDimensions }

        // Toggle object node visibility in-place
        scene.rootNode.childNodes(passingTest: { n, _ in n.name == Coordinator.objectTag })
            .forEach { $0.isHidden = !showObjects }

        // Update camera position only when view mode changes
        let camNode = context.coordinator.cameraNode ?? {
            let n = makeCamera(mode: viewMode)
            scene.rootNode.addChildNode(n)
            context.coordinator.cameraNode = n
            return n
        }()
        applyCamera(mode: viewMode, to: camNode)
        v.pointOfView = camNode
    }

    // MARK: - Scene builder (called once)

    private func buildScene(showDimensions: Bool, showObjects: Bool) -> SCNScene {
        let scene = SCNScene()

        for wall in room.walls {
            scene.rootNode.addChildNode(wallNode(wall))
            let label = dimensionLabel(for: wall)
            label.name   = Coordinator.dimensionTag
            label.isHidden = !showDimensions
            scene.rootNode.addChildNode(label)
        }
        for floor in room.floors {
            scene.rootNode.addChildNode(floorNode(floor))
        }
        for door in room.doors {
            scene.rootNode.addChildNode(apertureNode(door, color: .systemOrange))
        }
        for win in room.windows {
            scene.rootNode.addChildNode(apertureNode(win, color: .systemBlue))
        }
        for obj in room.objects {
            let n = objectNode(obj)
            n.name     = Coordinator.objectTag
            n.isHidden = !showObjects
            scene.rootNode.addChildNode(n)
        }
        scene.rootNode.addChildNode(gridPlane())
        return scene
    }

    // MARK: - Node builders (called once each during buildScene)

    private func wallNode(_ wall: CapturedRoom.Wall) -> SCNNode {
        let geo = SCNBox(width: CGFloat(wall.dimensions.x),
                         height: CGFloat(wall.dimensions.y),
                         length: 0.08, chamferRadius: 0)
        let mat = SCNMaterial()
        mat.diffuse.contents   = UIColor.white.withAlphaComponent(0.85)
        mat.specular.contents  = UIColor.white
        mat.lightingModel      = .physicallyBased
        mat.roughness.contents = 0.8
        mat.isDoubleSided      = true
        geo.materials = [mat]
        let node = SCNNode(geometry: geo)
        node.simdTransform = wall.transform
        return node
    }

    private func floorNode(_ floor: CapturedRoom.Floor) -> SCNNode {
        let geo = SCNPlane(width: CGFloat(floor.dimensions.x),
                           height: CGFloat(floor.dimensions.z))
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor.systemGray5
        mat.isDoubleSided    = true
        geo.materials = [mat]
        let node = SCNNode(geometry: geo)
        node.simdTransform = floor.transform
        node.eulerAngles.x = -.pi / 2
        return node
    }

    private func apertureNode(_ surface: any CapturedRoom.Surface, color: UIColor) -> SCNNode {
        let geo = SCNBox(width: CGFloat(surface.dimensions.x),
                         height: CGFloat(surface.dimensions.y),
                         length: 0.05, chamferRadius: 0)
        let mat = SCNMaterial()
        mat.diffuse.contents = color.withAlphaComponent(0.3)
        mat.isDoubleSided    = true
        geo.materials = [mat]
        let node = SCNNode(geometry: geo)
        node.simdTransform = surface.transform
        return node
    }

    private func objectNode(_ object: CapturedRoom.Object) -> SCNNode {
        let geo = SCNBox(width:  CGFloat(object.dimensions.x),
                         height: CGFloat(object.dimensions.y),
                         length: CGFloat(object.dimensions.z),
                         chamferRadius: 0.02)
        let mat = SCNMaterial()
        mat.diffuse.contents = objectColor(for: object.category)
        mat.transparency     = 0.6
        geo.materials = [mat]
        let node = SCNNode(geometry: geo)
        node.simdTransform = object.transform
        return node
    }

    private func dimensionLabel(for wall: CapturedRoom.Wall) -> SCNNode {
        let text = SCNText(string: String(format: "%.2fm", wall.dimensions.x), extrusionDepth: 0)
        text.font = UIFont.monospacedSystemFont(ofSize: 0.12, weight: .bold)
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor(red: 0.49, green: 0.83, blue: 0.99, alpha: 1)
        text.materials = [mat]
        let node = SCNNode(geometry: text)
        node.simdTransform = wall.transform
        node.position.y += Float(wall.dimensions.y) / 2 + 0.15
        node.position.x -= Float(wall.dimensions.x) / 4
        node.constraints = [SCNBillboardConstraint()]
        return node
    }

    private func gridPlane() -> SCNNode {
        let geo = SCNPlane(width: 20, height: 20)
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor.white.withAlphaComponent(0.03)
        mat.isDoubleSided    = true
        geo.materials = [mat]
        let node = SCNNode(geometry: geo)
        node.eulerAngles.x = -.pi / 2
        node.position.y    = -0.01
        return node
    }

    private func objectColor(for category: CapturedRoom.Object.Category) -> UIColor {
        switch category {
        case .bathtub, .shower: return .systemBlue
        case .toilet, .sink:    return .systemGray
        case .bed:              return .systemIndigo
        case .sofa:             return .systemBrown
        case .refrigerator:     return .systemCyan
        default:                return .systemGray2
        }
    }

    // MARK: - Lighting (added once to the scene)

    private func setupLighting(in scene: SCNScene) {
        let amb = SCNNode()
        amb.light           = SCNLight()
        amb.light!.type     = .ambient
        amb.light!.intensity = 400
        scene.rootNode.addChildNode(amb)

        let dir = SCNNode()
        dir.light            = SCNLight()
        dir.light!.type      = .directional
        dir.light!.intensity  = 800
        dir.light!.castsShadow = true
        dir.position = SCNVector3(5, 10, 5)
        dir.look(at: .init(0, 0, 0))
        scene.rootNode.addChildNode(dir)
    }

    // MARK: - Camera (updated in-place)

    private func makeCamera(mode: ModelViewer3D.ViewMode) -> SCNNode {
        let cam     = SCNCamera()
        cam.fieldOfView = 60
        let node    = SCNNode()
        node.camera = cam
        node.name   = Coordinator.cameraTag
        applyCamera(mode: mode, to: node)
        return node
    }

    private func applyCamera(mode: ModelViewer3D.ViewMode, to node: SCNNode) {
        switch mode {
        case .perspective: node.position = SCNVector3(4, 4, 4);     node.look(at: .init(0, 1, 0))
        case .topDown:     node.position = SCNVector3(0, 8, 0.001); node.look(at: .init(0, 0, 0))
        case .front:       node.position = SCNVector3(0, 1.5, 6);   node.look(at: .init(0, 1.5, 0))
        }
    }
}
