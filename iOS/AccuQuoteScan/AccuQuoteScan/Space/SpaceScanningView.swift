import SwiftUI
import ARKit
import SceneKit
import simd

// MARK: - SpaceScanningView (Tri-Mode Scanning build spec §3.1)
//
// Dark scan screen matching PoseFusionScanningView's conventions (top status
// pill, instruction text, bottom HUD), but with two states instead of one
// continuous scan: placingVolume (tap a detected plane to drop the capture
// box) then scanning (accumulate mesh + coverage inside that box). The
// #7DD3FC highlight tint on the capture volume outline is the one visual
// element unique to Space mode — everything else reuses existing pieces
// (CoverageRingView, ScanHUD's progress-bar styling).

struct SpaceScanningView: View {
    @ObservedObject var coordinator: SpaceCaptureCoordinator
    @ObservedObject private var tracker: SpaceCoverageTracker
    @State private var pulsing = false

    init(coordinator: SpaceCaptureCoordinator) {
        self.coordinator = coordinator
        self.tracker = coordinator.coverageTracker
    }

    private let highlightTint = Color(hex: "#7DD3FC")

    var body: some View {
        ZStack(alignment: .bottom) {
            if coordinator.arSession != nil {
                SpaceARHostRepresentable(coordinator: coordinator).ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            VStack(spacing: 0) {
                HStack {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(highlightTint)
                            .frame(width: 9, height: 9)
                            .shadow(color: highlightTint.opacity(pulsing ? 0.9 : 0.2), radius: pulsing ? 8 : 2)
                            .scaleEffect(pulsing ? 1.35 : 0.85)
                            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulsing)
                        Text(statusLabel)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(highlightTint.opacity(0.20))
                    .cornerRadius(22)
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(highlightTint.opacity(0.5), lineWidth: 1))
                    Spacer()
                    if case .scanning = coordinator.state {
                        Button { coordinator.finishCapture() } label: {
                            Text("Done")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16).padding(.vertical, 8)
                                .background(.ultraThinMaterial).cornerRadius(18)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)

                Spacer()

                Text(coordinator.instructionText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 16)

                if case .placingVolume = coordinator.state {
                    targetPicker
                        .padding(.bottom, 48)
                }

                if case .scanning = coordinator.state {
                    CoverageRingView(sectors: tracker.sectors, coverage: tracker.coverage, isComplete: tracker.isComplete)
                        .padding(.bottom, 48)
                        .onChange(of: tracker.isComplete) { isComplete in
                            // Auto-completion per §3.1: coverage > 92% stable for 2s.
                            if isComplete { coordinator.finishCapture() }
                        }
                }
            }
        }
        .ignoresSafeArea()
        .onAppear { pulsing = true }
        .animation(.easeInOut(duration: 0.3), value: coordinator.state.isScanning)
    }

    /// Void vs. frame — set before the placement tap since it decides
    /// finishCapture()'s extraction path (§3.2 treats them as two distinct
    /// measurements: OBB for a void, fitted rectangle + reveal for a frame).
    private var targetPicker: some View {
        HStack(spacing: 10) {
            ForEach([SpaceCaptureTarget.void, .frame], id: \.self) { target in
                TargetPickerButton(target: target, isSelected: coordinator.captureTarget == target, highlightTint: highlightTint) {
                    coordinator.captureTarget = target
                }
            }
        }
    }

    private var statusLabel: String {
        switch coordinator.state {
        case .placingVolume: return "Aim & tap"
        case .scanning:       return "Scanning"
        default:              return "Space"
        }
    }
}

private extension SpaceCaptureState {
    var isScanning: Bool {
        if case .scanning = self { return true }
        return false
    }
}

private struct TargetPickerButton: View {
    let target: SpaceCaptureTarget
    let isSelected: Bool
    let highlightTint: Color
    let action: () -> Void

    private var label: String {
        target == .void ? "Void / recess" : "Window / door frame"
    }
    private var textColor: Color { isSelected ? .black : .white }
    private var weight: Font.Weight { isSelected ? .semibold : .medium }
    private var backgroundColor: Color { isSelected ? highlightTint : Color.white.opacity(0.12) }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: weight))
                .foregroundColor(textColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(backgroundColor)
                .cornerRadius(18)
        }
    }
}

// MARK: - AR host (tap-to-place-volume + live mesh/box render)

final class SpaceARHostVC: UIViewController, ARSCNViewDelegate {
    private let coordinator: SpaceCaptureCoordinator
    private var sceneView: ARSCNView?
    private var volumeNode: SCNNode?

    private let highlightUIColor = UIColor(red: 0.49, green: 0.83, blue: 0.99, alpha: 1.0)  // #7DD3FC

    init(coordinator: SpaceCaptureCoordinator) {
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let v = ARSCNView(frame: UIScreen.main.bounds)
        v.automaticallyUpdatesLighting = true
        v.session = coordinator.arSession!
        v.delegate = self
        // Visualise the raw mesh while placing/scanning — this is what makes
        // "tap the detail" legible; without it the user is tapping a blank
        // camera feed with no sense of what ARKit has actually detected.
        v.debugOptions = [.showFeaturePoints]
        sceneView = v
        view = v

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        v.addGestureRecognizer(tap)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let session = coordinator.arSession else { return }
        session.run(coordinator.configuration())
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView?.session.pause()
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard case .placingVolume = coordinator.state, let sceneView else { return }
        let point = gesture.location(in: sceneView)

        // raycast against any detected plane (horizontal or vertical) — a
        // close-range detail like an under-sink void may only have a vertical
        // plane (the cabinet back) detected, not a floor.
        guard let query = sceneView.raycastQuery(from: point, allowing: .estimatedPlane, alignment: .any),
              let result = sceneView.session.raycast(query).first else { return }

        let t = result.worldTransform
        let worldPoint = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
        coordinator.placeVolume(at: worldPoint)
        addVolumeNode(center: worldPoint, sideLength: CaptureVolume.defaultSideLength)
    }

    private func addVolumeNode(center: SIMD3<Float>, sideLength: Float) {
        let box = SCNBox(width: CGFloat(sideLength), height: CGFloat(sideLength), length: CGFloat(sideLength), chamferRadius: 0)
        box.firstMaterial?.diffuse.contents = highlightUIColor.withAlphaComponent(0.12)
        box.firstMaterial?.isDoubleSided = true

        let node = SCNNode(geometry: box)
        node.position = SCNVector3(center.x, center.y, center.z)

        // Wireframe outline so the box edges read clearly against any background.
        let outline = SCNBox(width: CGFloat(sideLength), height: CGFloat(sideLength), length: CGFloat(sideLength), chamferRadius: 0)
        outline.firstMaterial?.diffuse.contents = highlightUIColor
        outline.firstMaterial?.fillMode = .lines
        let outlineNode = SCNNode(geometry: outline)
        node.addChildNode(outlineNode)

        sceneView?.scene.rootNode.addChildNode(node)
        volumeNode = node
    }
}

struct SpaceARHostRepresentable: UIViewControllerRepresentable {
    let coordinator: SpaceCaptureCoordinator
    func makeUIViewController(context: Context) -> SpaceARHostVC {
        SpaceARHostVC(coordinator: coordinator)
    }
    func updateUIViewController(_ vc: SpaceARHostVC, context: Context) {}
}
