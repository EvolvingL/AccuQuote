import SwiftUI
import SceneKit
import RoomPlan

// MARK: - ModelViewer3D
// Interactive 3D viewer using SceneKit — free pinch/rotate/pan.
// Walls = white, floor = grey, doors = orange apertures, windows = blue.

struct ModelViewer3D: View {
    let room: CapturedRoom
    @State private var showDimensions = true
    @State private var showObjects    = true
    @State private var viewMode: ViewMode = .perspective

    enum ViewMode: String, CaseIterable { case perspective = "3D", topDown = "Top", front = "Front" }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
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

            // 3D scene
            SceneKitView(room: room, showDimensions: showDimensions,
                         showObjects: showObjects, viewMode: viewMode)
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

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.allowsCameraControl     = true
        v.autoenablesDefaultLighting = false
        v.backgroundColor         = UIColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1)
        v.antialiasingMode        = .multisampling4X
        v.scene                   = buildScene()
        setupLighting(in: v.scene!)
        setCamera(on: v, mode: viewMode)
        return v
    }

    func updateUIView(_ v: SCNView, context: Context) {
        v.scene = buildScene()
        setupLighting(in: v.scene!)
        setCamera(on: v, mode: viewMode)
    }

    // MARK: - Scene builder

    private func buildScene() -> SCNScene {
        let scene = SCNScene()

        for wall in room.walls {
            scene.rootNode.addChildNode(wallNode(wall))
            if showDimensions { scene.rootNode.addChildNode(dimensionLabel(for: wall)) }
        }
        for floor in room.floors   { scene.rootNode.addChildNode(floorNode(floor)) }
        for door in room.doors     { scene.rootNode.addChildNode(apertureNode(door,   color: .systemOrange)) }
        for win  in room.windows   { scene.rootNode.addChildNode(apertureNode(win,    color: .systemBlue)) }
        if showObjects {
            for obj in room.objects { scene.rootNode.addChildNode(objectNode(obj)) }
        }
        scene.rootNode.addChildNode(gridPlane())
        return scene
    }

    private func wallNode(_ wall: CapturedRoom.Wall) -> SCNNode {
        let geo = SCNBox(width: CGFloat(wall.dimensions.x),
                         height: CGFloat(wall.dimensions.y),
                         length: 0.08, chamferRadius: 0)
        geo.firstMaterial?.diffuse.contents  = UIColor.white.withAlphaComponent(0.85)
        geo.firstMaterial?.specular.contents = UIColor.white
        geo.firstMaterial?.lightingModel     = .physicallyBased
        geo.firstMaterial?.roughness.contents = 0.8
        geo.firstMaterial?.isDoubleSided     = true
        let node = SCNNode(geometry: geo)
        node.simdTransform = wall.transform
        return node
    }

    private func floorNode(_ floor: CapturedRoom.Floor) -> SCNNode {
        let geo = SCNPlane(width: CGFloat(floor.dimensions.x), height: CGFloat(floor.dimensions.z))
        geo.firstMaterial?.diffuse.contents = UIColor.systemGray5
        geo.firstMaterial?.isDoubleSided    = true
        let node = SCNNode(geometry: geo)
        node.simdTransform    = floor.transform
        node.eulerAngles.x    = -.pi / 2
        return node
    }

    private func apertureNode(_ surface: any CapturedRoom.Surface, color: UIColor) -> SCNNode {
        let geo = SCNBox(width: CGFloat(surface.dimensions.x),
                         height: CGFloat(surface.dimensions.y),
                         length: 0.05, chamferRadius: 0)
        geo.firstMaterial?.diffuse.contents = color.withAlphaComponent(0.3)
        geo.firstMaterial?.isDoubleSided    = true
        let node = SCNNode(geometry: geo)
        node.simdTransform = surface.transform
        return node
    }

    private func objectNode(_ object: CapturedRoom.Object) -> SCNNode {
        let geo = SCNBox(width:  CGFloat(object.dimensions.x),
                         height: CGFloat(object.dimensions.y),
                         length: CGFloat(object.dimensions.z),
                         chamferRadius: 0.02)
        geo.firstMaterial?.diffuse.contents = objectColor(for: object.category)
        geo.firstMaterial?.transparency     = 0.6
        let node = SCNNode(geometry: geo)
        node.simdTransform = object.transform
        return node
    }

    private func dimensionLabel(for wall: CapturedRoom.Wall) -> SCNNode {
        let text = SCNText(string: String(format: "%.2fm", wall.dimensions.x), extrusionDepth: 0)
        text.font = UIFont.monospacedSystemFont(ofSize: 0.12, weight: .bold)
        text.firstMaterial?.diffuse.contents = UIColor(red: 0.49, green: 0.83, blue: 0.99, alpha: 1)
        let node = SCNNode(geometry: text)
        node.simdTransform = wall.transform
        node.position.y += Float(wall.dimensions.y) / 2 + 0.15
        node.position.x -= Float(wall.dimensions.x) / 4
        node.constraints = [SCNBillboardConstraint()]
        return node
    }

    private func gridPlane() -> SCNNode {
        let geo = SCNPlane(width: 20, height: 20)
        geo.firstMaterial?.diffuse.contents = UIColor.white.withAlphaComponent(0.03)
        geo.firstMaterial?.isDoubleSided    = true
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

    private func setupLighting(in scene: SCNScene) {
        let amb = SCNNode(); amb.light = SCNLight()
        amb.light!.type = .ambient; amb.light!.intensity = 400
        scene.rootNode.addChildNode(amb)

        let dir = SCNNode(); dir.light = SCNLight()
        dir.light!.type = .directional; dir.light!.intensity = 800
        dir.light!.castsShadow = true
        dir.position = SCNVector3(5, 10, 5)
        dir.look(at: .init(0, 0, 0))
        scene.rootNode.addChildNode(dir)
    }

    private func setCamera(on view: SCNView, mode: ModelViewer3D.ViewMode) {
        let cam     = SCNCamera(); cam.fieldOfView = 60
        let camNode = SCNNode(); camNode.camera = cam
        switch mode {
        case .perspective: camNode.position = SCNVector3(4, 4, 4);     camNode.look(at: .init(0, 1, 0))
        case .topDown:     camNode.position = SCNVector3(0, 8, 0.001); camNode.look(at: .init(0, 0, 0))
        case .front:       camNode.position = SCNVector3(0, 1.5, 6);   camNode.look(at: .init(0, 1.5, 0))
        }
        view.scene?.rootNode.addChildNode(camNode)
        view.pointOfView = camNode
    }
}
