import RealityKit
import ARKit
import simd
import UIKit

// MARK: - WallHighlightEntity
// Placed on each detected wall. Light blue (#7DD3FC) corner L-bars animate from
// invisible → dim → bright as RoomPlan confidence increases.
// Opacity is animated via a cancellable Task to prevent concurrent animation
// loops fighting each other when wall state changes rapidly.

class WallHighlightEntity: Entity, HasModel, HasAnchoring {

    // MARK: - Colour (#7DD3FC)
    static let lightBlue = UIColor(red: 0.49, green: 0.83, blue: 0.99, alpha: 1.00)

    // Cancels any in-progress opacity animation before starting a new one
    private var opacityTask: Task<Void, Never>?

    // MARK: - Init
    required init() { super.init() }

    static func make(for wall: TrackedWall) -> WallHighlightEntity {
        let e = WallHighlightEntity()
        e.configure(wall: wall)
        return e
    }

    // MARK: - Configure / reconfigure

    func configure(wall: TrackedWall) {
        children.forEach { $0.removeFromParent() }
        opacityTask?.cancel()
        opacityTask = nil

        let w = wall.worldSize.x
        let h = wall.worldSize.y
        let barT: Float = 0.025
        let barL: Float = min(0.35, w * 0.25)
        let barH: Float = min(0.35, h * 0.25)

        // Four corner L-bars (each corner = horizontal + vertical bar)
        addBar(size: [barL, barT, barT], pos: [-w/2 + barL/2,  h/2,          0.01])
        addBar(size: [barT, barH, barT], pos: [-w/2,            h/2 - barH/2, 0.01])
        addBar(size: [barL, barT, barT], pos: [ w/2 - barL/2,  h/2,          0.01])
        addBar(size: [barT, barH, barT], pos: [ w/2,            h/2 - barH/2, 0.01])
        addBar(size: [barL, barT, barT], pos: [-w/2 + barL/2, -h/2,          0.01])
        addBar(size: [barT, barH, barT], pos: [-w/2,           -h/2 + barH/2, 0.01])
        addBar(size: [barL, barT, barT], pos: [ w/2 - barL/2, -h/2,          0.01])
        addBar(size: [barT, barH, barT], pos: [ w/2,           -h/2 + barH/2, 0.01])

        // Subtle full-wall face glow
        let faceMat  = UnlitMaterial(color: UIColor(red: 0.49, green: 0.83, blue: 0.99, alpha: 0.04))
        let faceMesh = ModelEntity(mesh: .generatePlane(width: w * 0.96, height: h * 0.96),
                                   materials: [faceMat])
        faceMesh.position = [0, 0, 0.005]
        addChild(faceMesh)

        self.transform = Transform(matrix: wall.worldTransform)
        update(to: wall.highlightState, animated: false)
    }

    // MARK: - State update (called on every RoomPlan tick from AROverlayCoordinator)

    func update(to state: TrackedWall.HighlightState, animated: Bool = true) {
        let targetAlpha: Float
        let shouldPulse: Bool

        switch state {
        case .none:     targetAlpha = 0.00; shouldPulse = false
        case .partial:  targetAlpha = 0.35; shouldPulse = false
        case .good:     targetAlpha = 0.70; shouldPulse = false
        case .complete: targetAlpha = 1.00; shouldPulse = true
        }

        if animated {
            animateOpacity(to: targetAlpha)
        } else {
            applyOpacity(targetAlpha)
        }

        if shouldPulse {
            startPulse()
            // Dispatch to main thread — UIKit haptics must run there
            DispatchQueue.main.async { HapticService.shared.lightImpact() }
        }
    }

    // MARK: - Pulse (plays once on .complete)

    private func startPulse() {
        let up   = Transform(scale: .init(repeating: 1.04))
        let down = Transform(scale: .init(repeating: 1.00))
        move(to: up,   relativeTo: parent, duration: 0.15, timingFunction: .easeOut)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.move(to: down, relativeTo: self?.parent, duration: 0.15, timingFunction: .easeIn)
        }
    }

    // MARK: - Smooth opacity animation
    // Cancels any running animation before starting a new one, preventing
    // concurrent Tasks from fighting over material alpha values.

    private func animateOpacity(to targetAlpha: Float, duration: TimeInterval = 0.3) {
        opacityTask?.cancel()

        let steps    = 12
        let interval = duration / Double(steps)
        let modelChildren = children.compactMap { $0 as? ModelEntity }

        // Sample current alpha from the first bar child (default 0 if unavailable)
        let currentAlpha: Float = {
            guard let first = modelChildren.first,
                  let mat = first.model?.materials.first as? UnlitMaterial,
                  let components = mat.color.tint.cgColor?.components,
                  components.count >= 4
            else { return 0 }
            return Float(components[3])
        }()

        opacityTask = Task { @MainActor in
            for step in 1...steps {
                guard !Task.isCancelled else { return }
                let t     = Float(step) / Float(steps)
                let alpha = currentAlpha + (targetAlpha - currentAlpha) * t
                self.applyOpacity(alpha, to: modelChildren)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    // Applies a given alpha immediately to all bar children (no animation)
    private func applyOpacity(_ alpha: Float, to modelChildren: [ModelEntity]? = nil) {
        let targets = modelChildren ?? children.compactMap { $0 as? ModelEntity }
        let color   = UIColor(red: 0.49, green: 0.83, blue: 0.99, alpha: CGFloat(alpha))
        for model in targets {
            guard var mat = model.model?.materials.first as? UnlitMaterial else { continue }
            mat.color = .init(tint: color)
            model.model?.materials = [mat]
        }
    }

    // MARK: - Helpers

    private func addBar(size: SIMD3<Float>, pos: SIMD3<Float>) {
        let mat    = UnlitMaterial(color: UIColor(red: 0.49, green: 0.83, blue: 0.99, alpha: 0.25))
        let entity = ModelEntity(mesh: .generateBox(size: size, cornerRadius: 0.008),
                                 materials: [mat])
        entity.position = pos
        addChild(entity)
    }
}
