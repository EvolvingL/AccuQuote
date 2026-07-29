import SwiftUI
import SceneKit
import RoomPlan
import simd
import QuickLook

// MARK: - ScanViewer3D (Tri-Mode Scanning build spec §6)
//
// One shared viewer for all three modes (§6.1: "One component, ScanViewer3D,
// used by all three modes"). Room mode hands it a CapturedRoom (RoomPlan's
// parametric surfaces); Space mode hands it a raw triangle mesh
// (SpaceMeshExtraction.ExtractedTriangle, already frozen after capture).
// ViewerContent is the seam between the two — everything below that point
// (camera rig, gestures, control bar, background) is mode-agnostic.
//
// Originally Room-only (Phase 3, ported from AccuScan's ModelViewer3D.swift).
// Generalized in Phase 5 to satisfy §6.1's "one component" requirement and
// wired into ResultView (Room's real success path) and both Space result
// screens, replacing Space mode's bespoke SpaceMeshMeasureView.

enum ViewerContent {
    case room(CapturedRoom)
    case spaceMesh([SpaceMeshExtraction.ExtractedTriangle])
}

struct ScanViewer3D: View {
    let content: ViewerContent
    /// Tap-to-measure callback (Space mode only, §3.2) — when non-nil, taps
    /// on the mesh are captured and reported here instead of being consumed
    /// by the orbit-rig's own gesture handling. Room mode passes nil.
    var onMeasureTap: ((SIMD3<Float>) -> Void)?

    @State private var showDimensions = true
    @State private var showObjects    = true
    @State private var showWireframe  = false
    @State private var viewMode: ViewMode = .perspective
    @State private var resetToken = 0   // bumped to trigger the Reset button's animated recentre

    // AR Quick Look (§6.3) — exports a fresh USDZ on demand and hands it to
    // QLPreviewController, which natively offers "View in AR" with no ARKit
    // session code needed here.
    @State private var arQuickLookURL: URL?
    @State private var isPreparingARQuickLook = false
    @State private var arQuickLookError: String?

    // Share sheet (§6.3 bottom bar "Share") — exports the same USDZ AR Quick
    // Look would use and hands it to the existing ShareSheet pattern.
    @State private var shareURL: URL?
    @State private var isPreparingShare = false

    private var isSpaceContent: Bool {
        if case .spaceMesh = content { return true }
        return false
    }

    enum ViewMode: String, CaseIterable { case perspective = "3D", topDown = "Top", front = "Front" }

    var body: some View {
        ZStack(alignment: .bottom) {
            // §6.3 — light AQ.fill → white vertical gradient background;
            // the dark treatment stays exclusive to live scanning, not the
            // post-capture viewer.
            LinearGradient(colors: [AQ.fill, Color.white], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScanSceneKitView(
                content: content,
                showDimensions: showDimensions,
                showObjects: showObjects,
                showWireframe: showWireframe,
                viewMode: viewMode,
                resetToken: resetToken,
                onMeasureTap: onMeasureTap
            )

            VStack {
                Spacer()
                controlBar
                    .padding(.bottom, 16)
            }
        }
        .alert("Couldn't prepare AR preview", isPresented: .constant(arQuickLookError != nil), actions: {
            Button("OK") { arQuickLookError = nil }
        }, message: {
            Text(arQuickLookError ?? "")
        })
        .fullScreenCover(item: $arQuickLookURL) { url in
            ScanARQuickLookView(usdzURL: url)
                .ignoresSafeArea()
        }
        .sheet(item: $shareURL) { url in
            ShareSheet(url: url)
        }
    }

    // MARK: - §6.3 bottom capsule control bar: Reset · Dimensions · Share · AR

    private var controlBar: some View {
        HStack(spacing: 4) {
            controlButton(systemImage: "arrow.counterclockwise", label: "Reset") {
                resetToken += 1
            }
            Divider().frame(height: 20)
            controlButton(
                systemImage: showDimensions ? "ruler.fill" : "ruler",
                label: "Dimensions",
                tinted: showDimensions
            ) {
                withAnimation { showDimensions.toggle() }
            }
            if isSpaceContent {
                Divider().frame(height: 20)
                controlButton(
                    systemImage: showWireframe ? "square.grid.3x3.fill" : "square.grid.3x3",
                    label: "Mesh",
                    tinted: showWireframe
                ) {
                    withAnimation { showWireframe.toggle() }
                }
            }
            Divider().frame(height: 20)
            if isPreparingShare {
                ProgressView().tint(AQ.blue).frame(width: 44, height: 32)
            } else {
                controlButton(systemImage: "square.and.arrow.up", label: "Share") {
                    startShare()
                }
            }
            Divider().frame(height: 20)
            if isPreparingARQuickLook {
                ProgressView().tint(AQ.blue).frame(width: 44, height: 32)
            } else {
                controlButton(systemImage: "arkit", label: "AR") {
                    startARQuickLook()
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(AQ.rule, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
    }

    private func controlButton(systemImage: String, label: String, tinted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                Text(label)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(tinted ? AQ.blue : AQ.ink)
            .frame(width: 52, height: 40)
        }
    }

    // MARK: - Export (shared by AR Quick Look + Share)

    private func exportUSDZ() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("scan-export-\(UUID().uuidString)")
            .appendingPathExtension("usdz")
        switch content {
        case .room(let room):
            try room.export(to: url, exportOptions: [.mesh, .parametric])
        case .spaceMesh(let triangles):
            let files = try SpaceMeshExport.export(triangles: triangles, scanID: UUID().uuidString)
            // SpaceMeshExport already wrote a USDZ under aq_scans/ — copy it to
            // a temp location so both this viewer's callers and the persisted
            // aq_scans/ copy exist independently (the temp one is transient,
            // used for AR Quick Look / share and safe to overwrite next time).
            try? FileManager.default.removeItem(at: url)
            try FileManager.default.copyItem(at: files.usdzURL, to: url)
        }
        return url
    }

    private func startARQuickLook() {
        guard !isPreparingARQuickLook else { return }
        isPreparingARQuickLook = true
        Task {
            defer { isPreparingARQuickLook = false }
            do {
                arQuickLookURL = try exportUSDZ()
            } catch {
                arQuickLookError = "Could not generate the AR model. Please try again."
            }
        }
    }

    private func startShare() {
        guard !isPreparingShare else { return }
        isPreparingShare = true
        Task {
            defer { isPreparingShare = false }
            if let url = try? exportUSDZ() {
                shareURL = url
            }
        }
    }
}

// URL: Identifiable conformance (needed for .fullScreenCover(item:)/.sheet(item:))
// is already declared in Views.swift, next to ShareSheet's identical need —
// reused here rather than redeclared, since Swift only allows one conformance
// of a type to a given protocol per module.

// MARK: - SceneKit wrapper

struct ScanSceneKitView: UIViewRepresentable {
    let content: ViewerContent
    let showDimensions: Bool
    let showObjects: Bool
    let showWireframe: Bool
    let viewMode: ScanViewer3D.ViewMode
    let resetToken: Int
    var onMeasureTap: ((SIMD3<Float>) -> Void)?

    // MARK: Coordinator
    // Holds the SCNScene, the orbit rig, and gesture state. updateUIView
    // mutates nodes in-place instead of rebuilding the entire scene.
    //
    // Orbit rig (§6.2 — "object stays centred"): a pivot SCNNode sits at the
    // model's bounding-box centre; the camera is a child of the pivot offset
    // along +Z by the current zoom distance. Rotating the PIVOT (not the
    // camera) around its own Y then X axes gives yaw/pitch orbit while the
    // camera always looks at the pivot's origin — the model can never drift
    // off-centre because the pivot's origin never moves. Pinch changes the
    // camera's local Z offset (zoom); it never touches the pivot's position,
    // so there is no free-pan capability at all, matching §6.2's explicit
    // "two-finger pan is deliberately disabled" requirement.
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var scene: SCNScene?
        weak var sceneView: SCNView?
        weak var pivotNode: SCNNode?
        weak var cameraNode: SCNNode?
        var lastAppliedViewMode: ScanViewer3D.ViewMode?
        var lastResetToken: Int = 0
        var onMeasureTap: ((SIMD3<Float>) -> Void)?

        static let dimensionTag = "dim"
        static let objectTag    = "obj"
        static let pivotTag     = "pivot"
        static let wireframeTag = "wireframe"

        private var yaw: Float = 0
        private var pitch: Float = 0
        private var zoomDistance: Float = 6
        private var boundingRadius: Float = 4

        private static let pitchMin: Float = -10 * .pi / 180
        private static let pitchMax: Float =  85 * .pi / 180
        private static let zoomMinFactor: Float = 0.4
        private static let zoomMaxFactor: Float = 6.0

        private static let defaultYaw:   Float = .pi / 4
        private static let defaultPitch: Float = .pi / 6

        private var yawVelocity: Float = 0
        private var pitchVelocity: Float = 0
        private var displayLink: CADisplayLink?
        private static let inertiaDecay: Float = 0.92
        private static let inertiaStopThreshold: Float = 0.0005

        // §6.3 — dimension labels fade in only when camera distance < 2.5x
        // bounding radius, to avoid label soup at far zoom.
        private static let labelFadeInZoomFactor: Float = 2.5
        private var labelsCurrentlyVisible = false

        deinit { displayLink?.invalidate() }

        func setUpOrbitRig(in scene: SCNScene, sceneView: SCNView, initialMode: ScanViewer3D.ViewMode) {
            self.sceneView = sceneView
            boundingRadius = Self.computeBoundingRadius(of: scene)
            zoomDistance = boundingRadius * 1.5

            let pivot = SCNNode()
            pivot.name = Self.pivotTag
            scene.rootNode.addChildNode(pivot)
            self.pivotNode = pivot

            let cam = SCNCamera()
            cam.fieldOfView = 60
            let camNode = SCNNode()
            camNode.camera = cam
            camNode.position = SCNVector3(0, 0, zoomDistance)
            pivot.addChildNode(camNode)
            self.cameraNode = camNode
            sceneView.pointOfView = camNode

            lastAppliedViewMode = initialMode
            applyPreset(mode: initialMode, animated: false)
        }

        private static func computeBoundingRadius(of scene: SCNScene) -> Float {
            let (min, max) = scene.rootNode.boundingBox
            let extent = SCNVector3(max.x - min.x, max.y - min.y, max.z - min.z)
            let radius = simd_length(SIMD3<Float>(extent.x, extent.y, extent.z)) / 2
            return radius.isFinite && radius > 0.1 ? radius : 4
        }

        func applyPreset(mode: ScanViewer3D.ViewMode, animated: Bool) {
            let (targetYaw, targetPitch, targetZoomFactor): (Float, Float, Float)
            switch mode {
            case .perspective: (targetYaw, targetPitch, targetZoomFactor) = (Self.defaultYaw, Self.defaultPitch, 1.5)
            case .topDown:     (targetYaw, targetPitch, targetZoomFactor) = (0, Self.pitchMax, 2.0)
            case .front:       (targetYaw, targetPitch, targetZoomFactor) = (0, 0, 1.8)
            }
            setOrbit(yaw: targetYaw, pitch: targetPitch,
                     zoomDistance: boundingRadius * targetZoomFactor, animated: animated)
        }

        func attachGestures(to view: SCNView) {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.delegate = self
            view.addGestureRecognizer(pan)

            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.delegate = self
            view.addGestureRecognizer(pinch)

            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            doubleTap.numberOfTapsRequired = 2
            view.addGestureRecognizer(doubleTap)

            // Single-tap for measure mode (Space mode only — onMeasureTap is
            // nil for Room content). Requires the double-tap above to fail
            // first so a reset double-tap isn't also read as two single taps.
            if onMeasureTap != nil {
                let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
                singleTap.require(toFail: doubleTap)
                view.addGestureRecognizer(singleTap)
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            let translation = gesture.translation(in: view)

            switch gesture.state {
            case .changed:
                stopInertia()
                let dYaw   = Float(translation.x / view.bounds.width)  * .pi
                let dPitch = Float(translation.y / view.bounds.height) * .pi
                setOrbit(yaw: yaw + dYaw, pitch: pitch + dPitch, zoomDistance: zoomDistance, animated: false)
                gesture.setTranslation(.zero, in: view)

            case .ended, .cancelled:
                let velocity = gesture.velocity(in: view)
                yawVelocity   = Float(velocity.x / view.bounds.width)  * .pi / 60
                pitchVelocity = Float(velocity.y / view.bounds.height) * .pi / 60
                startInertiaIfNeeded()

            default:
                break
            }
        }

        @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard gesture.state == .changed || gesture.state == .began else { return }
            stopInertia()
            let newDistance = zoomDistance / Float(gesture.scale)
            setOrbit(yaw: yaw, pitch: pitch, zoomDistance: newDistance, animated: false)
            gesture.scale = 1
        }

        @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            resetToDefault()
        }

        @objc private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? SCNView, let onMeasureTap else { return }
            let point = gesture.location(in: view)
            let results = view.hitTest(point, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue])
            guard let hit = results.first else { return }
            let world = hit.worldCoordinates
            onMeasureTap(SIMD3<Float>(world.x, world.y, world.z))
        }

        func resetToDefault() {
            stopInertia()
            setOrbit(yaw: Self.defaultYaw, pitch: Self.defaultPitch,
                      zoomDistance: boundingRadius * 1.5, animated: true)
        }

        // Fly-to primitive for the Review & Guided Re-scan screen's "Show me"
        // button (§5.4 step 2) — not called yet (ScanNeedsReviewView doesn't
        // inject marker world-anchors), built alongside the rest of the rig.
        func flyTo(worldPoint: SCNVector3, animated: Bool = true) {
            guard let pivot = pivotNode else { return }
            let pivotWorldPos = pivot.simdWorldPosition
            let toPoint = SIMD3<Float>(worldPoint.x, worldPoint.y, worldPoint.z) - pivotWorldPos
            guard simd_length(toPoint) > 0.001 else { return }
            let targetYaw = atan2(toPoint.x, toPoint.z)
            let horizontalDist = simd_length(SIMD2<Float>(toPoint.x, toPoint.z))
            let targetPitch = atan2(toPoint.y, horizontalDist)
            setOrbit(yaw: targetYaw,
                      pitch: min(max(targetPitch, Self.pitchMin), Self.pitchMax),
                      zoomDistance: zoomDistance, animated: animated)
        }

        private func startInertiaIfNeeded() {
            guard abs(yawVelocity) > Self.inertiaStopThreshold || abs(pitchVelocity) > Self.inertiaStopThreshold else { return }
            guard displayLink == nil else { return }
            let link = CADisplayLink(target: self, selector: #selector(stepInertia))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        private func stopInertia() {
            displayLink?.invalidate()
            displayLink = nil
            yawVelocity = 0
            pitchVelocity = 0
        }

        @objc private func stepInertia() {
            guard abs(yawVelocity) > Self.inertiaStopThreshold || abs(pitchVelocity) > Self.inertiaStopThreshold else {
                stopInertia()
                return
            }
            setOrbit(yaw: yaw + yawVelocity, pitch: pitch + pitchVelocity, zoomDistance: zoomDistance, animated: false)
            yawVelocity   *= Self.inertiaDecay
            pitchVelocity *= Self.inertiaDecay
        }

        private func setOrbit(yaw newYaw: Float, pitch newPitch: Float, zoomDistance newZoom: Float, animated: Bool) {
            yaw = newYaw
            pitch = min(max(newPitch, Self.pitchMin), Self.pitchMax)
            let minZoom = boundingRadius * Self.zoomMinFactor
            let maxZoom = boundingRadius * Self.zoomMaxFactor
            zoomDistance = min(max(newZoom, minZoom), maxZoom)
            updateTransform(animated: animated)
            updateLabelVisibility(animated: true)
        }

        private func updateTransform(animated: Bool) {
            guard let pivot = pivotNode, let cam = cameraNode else { return }
            let apply = {
                pivot.eulerAngles = SCNVector3(self.pitch, self.yaw, 0)
                cam.position = SCNVector3(0, 0, self.zoomDistance)
            }
            if animated {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.45
                SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                apply()
                SCNTransaction.commit()
            } else {
                SCNTransaction.begin()
                SCNTransaction.disableActions = true
                apply()
                SCNTransaction.commit()
            }
        }

        // Pure threshold check, pulled out of updateLabelVisibility so it's
        // fixture-testable without an SCNScene (see DevToolsChecks.
        // dimensionLabelsFadeAtCorrectDistance) — camera distance from the
        // pivot IS zoomDistance by construction of this rig, so no separate
        // distance query is needed at the call site either.
        static func shouldShowLabels(zoomDistance: Float, boundingRadius: Float) -> Bool {
            zoomDistance < boundingRadius * labelFadeInZoomFactor
        }

        // §6.3 — dimension labels fade in over 300ms only inside 2.5x the
        // bounding radius; fade back out past it.
        private func updateLabelVisibility(animated: Bool) {
            guard let scene else { return }
            let shouldShow = Self.shouldShowLabels(zoomDistance: zoomDistance, boundingRadius: boundingRadius)
            guard shouldShow != labelsCurrentlyVisible else { return }
            labelsCurrentlyVisible = shouldShow

            let labelNodes = scene.rootNode.childNodes(passingTest: { n, _ in n.name == Self.dimensionTag })
            for node in labelNodes {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = animated ? 0.3 : 0
                node.opacity = shouldShow ? 1.0 : 0.0
                SCNTransaction.commit()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        let c = Coordinator()
        c.onMeasureTap = onMeasureTap
        return c
    }

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.allowsCameraControl        = false
        v.autoenablesDefaultLighting = false
        v.backgroundColor            = .clear   // the light gradient lives behind this view in ScanViewer3D
        v.antialiasingMode           = .multisampling4X

        let scene = buildScene(content: content, showDimensions: showDimensions, showObjects: showObjects, showWireframe: showWireframe)
        context.coordinator.scene = scene
        v.scene = scene

        setupLighting(in: scene)
        addContactShadow(to: scene)
        context.coordinator.setUpOrbitRig(in: scene, sceneView: v, initialMode: viewMode)
        context.coordinator.attachGestures(to: v)
        context.coordinator.lastResetToken = resetToken

        return v
    }

    func updateUIView(_ v: SCNView, context: Context) {
        guard let scene = context.coordinator.scene else { return }

        scene.rootNode.childNodes(passingTest: { n, _ in n.name == Coordinator.dimensionTag })
            .forEach { $0.isHidden = !showDimensions }

        scene.rootNode.childNodes(passingTest: { n, _ in n.name == Coordinator.objectTag })
            .forEach { $0.isHidden = !showObjects }

        scene.rootNode.childNodes(passingTest: { n, _ in n.name == Coordinator.wireframeTag })
            .forEach { $0.isHidden = !showWireframe }

        if context.coordinator.lastAppliedViewMode != viewMode {
            context.coordinator.lastAppliedViewMode = viewMode
            context.coordinator.applyPreset(mode: viewMode, animated: true)
        }

        if context.coordinator.lastResetToken != resetToken {
            context.coordinator.lastResetToken = resetToken
            context.coordinator.resetToDefault()
        }
    }

    // MARK: - Scene builder (called once)

    private func buildScene(content: ViewerContent, showDimensions: Bool, showObjects: Bool, showWireframe: Bool) -> SCNScene {
        switch content {
        case .room(let room):
            return buildRoomScene(room, showDimensions: showDimensions, showObjects: showObjects)
        case .spaceMesh(let triangles):
            return buildSpaceMeshScene(triangles, showWireframe: showWireframe)
        }
    }

    // MARK: Room mode scene (RoomPlan parametric surfaces)

    private func buildRoomScene(_ room: CapturedRoom, showDimensions: Bool, showObjects: Bool) -> SCNScene {
        let scene = SCNScene()

        for wall in room.walls {
            guard let node = wallNode(wall) else { continue }
            scene.rootNode.addChildNode(node)
            let label = dimensionLabel(for: wall)
            label.name   = Coordinator.dimensionTag
            label.isHidden = !showDimensions
            scene.rootNode.addChildNode(label)
        }
        if #available(iOS 17, *) {
            for floor in room.floors {
                scene.rootNode.addChildNode(floorNode(floor))
            }
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

    private func wallNode(_ wall: CapturedRoom.Surface) -> SCNNode? {
        guard wall.dimensions.x.isFinite, wall.dimensions.y.isFinite,
              wall.dimensions.x > 0, wall.dimensions.y > 0,
              wall.transform.columns.3.x.isFinite,
              wall.transform.columns.3.y.isFinite,
              wall.transform.columns.3.z.isFinite else { return nil }
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

    private func floorNode(_ floor: CapturedRoom.Surface) -> SCNNode {
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

    private func apertureNode(_ surface: CapturedRoom.Surface, color: UIColor) -> SCNNode {
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

    private func dimensionLabel(for wall: CapturedRoom.Surface) -> SCNNode {
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

    private func objectColor(for category: CapturedRoom.Object.Category) -> UIColor {
        switch category {
        case .bathtub:          return .systemBlue
        case .toilet, .sink:    return .systemGray
        case .bed:              return .systemIndigo
        case .sofa:             return .systemBrown
        case .refrigerator:     return .systemCyan
        default:                return .systemGray2
        }
    }

    // MARK: Space mode scene (raw ARMeshAnchor-derived triangles)

    private func buildSpaceMeshScene(_ triangles: [SpaceMeshExtraction.ExtractedTriangle], showWireframe: Bool) -> SCNScene {
        let scene = SCNScene()
        guard !triangles.isEmpty else {
            scene.rootNode.addChildNode(gridPlane())
            return scene
        }

        var vertices: [SCNVector3] = []
        vertices.reserveCapacity(triangles.count * 3)
        var indices: [Int32] = []
        for (i, tri) in triangles.enumerated() {
            vertices.append(SCNVector3(tri.v0.x, tri.v0.y, tri.v0.z))
            vertices.append(SCNVector3(tri.v1.x, tri.v1.y, tri.v1.z))
            vertices.append(SCNVector3(tri.v2.x, tri.v2.y, tri.v2.z))
            let base = Int32(i * 3)
            indices.append(contentsOf: [base, base + 1, base + 2])
        }

        let source = SCNGeometrySource(vertices: vertices)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let geometry = SCNGeometry(sources: [source], elements: [element])
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor(red: 0.49, green: 0.83, blue: 0.99, alpha: 1.0)
        mat.isDoubleSided = true
        mat.lightingModel = .physicallyBased
        mat.roughness.contents = 0.7
        geometry.materials = [mat]

        let meshNode = SCNNode(geometry: geometry)
        scene.rootNode.addChildNode(meshNode)

        // §6.3 "Show mesh" wireframe overlay in #7DD3FC — a second node
        // sharing the same geometry with a line-fill material, toggled
        // independently of the solid mesh via the wireframeTag.
        let wireGeometry = geometry.copy() as! SCNGeometry
        let wireMat = SCNMaterial()
        wireMat.diffuse.contents = UIColor(red: 0.49, green: 0.83, blue: 0.99, alpha: 1.0)
        wireMat.fillMode = .lines
        wireMat.isDoubleSided = true
        wireGeometry.materials = [wireMat]
        let wireNode = SCNNode(geometry: wireGeometry)
        wireNode.name = Coordinator.wireframeTag
        wireNode.isHidden = !showWireframe
        scene.rootNode.addChildNode(wireNode)

        scene.rootNode.addChildNode(gridPlane())
        return scene
    }

    // MARK: Shared

    private func gridPlane() -> SCNNode {
        let geo = SCNPlane(width: 20, height: 20)
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor.black.withAlphaComponent(0.03)
        mat.isDoubleSided    = true
        geo.materials = [mat]
        let node = SCNNode(geometry: geo)
        node.eulerAngles.x = -.pi / 2
        node.position.y    = -0.01
        return node
    }

    // §6.3 "soft contact shadow under the model" — a large shadow-only plane
    // beneath the geometry. .colorBufferWriteMask = [] means it renders no
    // colour of its own, only receives the directional light's shadow, so it
    // reads as a soft floor shadow rather than a visible grey disc.
    private func addContactShadow(to scene: SCNScene) {
        let geo = SCNPlane(width: 40, height: 40)
        let mat = SCNMaterial()
        mat.lightingModel = .constant
        mat.writesToDepthBuffer = false
        mat.colorBufferWriteMask = []
        geo.materials = [mat]
        let node = SCNNode(geometry: geo)
        node.eulerAngles.x = -.pi / 2
        node.position.y = -0.005
        node.renderingOrder = -1
        node.castsShadow = false
        scene.rootNode.addChildNode(node)
    }

    private func setupLighting(in scene: SCNScene) {
        let amb = SCNNode()
        amb.light           = SCNLight()
        amb.light!.type     = .ambient
        amb.light!.intensity = 500
        amb.light!.color    = UIColor.white
        scene.rootNode.addChildNode(amb)

        let dir = SCNNode()
        dir.light            = SCNLight()
        dir.light!.type      = .directional
        dir.light!.intensity  = 900
        dir.light!.castsShadow = true
        dir.light!.shadowColor = UIColor.black.withAlphaComponent(0.25)
        dir.light!.shadowRadius = 8
        dir.position = SCNVector3(5, 10, 5)
        dir.look(at: .init(0, 0, 0))
        scene.rootNode.addChildNode(dir)
    }
}

// MARK: - ScanARQuickLookView (§6.3 AR button)

struct ScanARQuickLookView: UIViewControllerRepresentable {
    let usdzURL: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: usdzURL) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as QLPreviewItem
        }
    }
}
