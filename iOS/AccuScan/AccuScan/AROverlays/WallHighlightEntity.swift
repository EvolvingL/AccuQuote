import RealityKit
import ARKit
import simd
import UIKit

// MARK: - WallHighlightEntity
// Light blue (#7DD3FC) corner L-bars that animate as RoomPlan confidence increases.
// Uses a cancellable Task for opacity animation to prevent concurrent loops.

class WallHighlightEntity: Entity, HasModel, HasAnchoring {

    // Pre-built UIColor instances — avoids allocating on every animation step
    private static let r: CGFloat = 0.49
    private static let g: CGFloat = 0.83
    private static let b: CGFloat = 0.99
    static func alphaColor(_ alpha: CGFloat) -> UIColor {
        UIColor(red: r, green: g, blue: b, alpha: alpha)
    }

    private var opacityTask: Task<Void, Never>?
    // Track current alpha to avoid unnecessary material writes
    private var currentAlpha: Float = 0
    // Cached bar children — avoids compactMap on every animation step
    private var barChildren: [ModelEntity] = []

    required init() { super.init() }

    static func make(for wall: TrackedWall) -> WallHighlightEntity {
        let e = WallHighlightEntity()
        e.configure(wall: wall)
        return e
    }

    // MARK: - Configure

    func configure(wall: TrackedWall) {
        opacityTask?.cancel()
        opacityTask = nil
        children.forEach { $0.removeFromParent() }
        barChildren.removeAll(keepingCapacity: true)
        currentAlpha = 0

        let w = wall.worldSize.x
        let h = wall.worldSize.y
        let barT: Float = 0.025
        let barL: Float = min(0.35, w * 0.25)
        let barH: Float = min(0.35, h * 0.25)

        addBar(size: [barL, barT, barT], pos: [-w/2 + barL/2,  h/2,           0.01])
        addBar(size: [barT, barH, barT], pos: [-w/2,            h/2 - barH/2,  0.01])
        addBar(size: [barL, barT, barT], pos: [ w/2 - barL/2,  h/2,           0.01])
        addBar(size: [barT, barH, barT], pos: [ w/2,            h/2 - barH/2,  0.01])
        addBar(size: [barL, barT, barT], pos: [-w/2 + barL/2, -h/2,           0.01])
        addBar(size: [barT, barH, barT], pos: [-w/2,           -h/2 + barH/2,  0.01])
        addBar(size: [barL, barT, barT], pos: [ w/2 - barL/2, -h/2,           0.01])
        addBar(size: [barT, barH, barT], pos: [ w/2,           -h/2 + barH/2,  0.01])

        let faceMat  = UnlitMaterial(color: Self.alphaColor(0.04))
        let faceMesh = ModelEntity(mesh: .generatePlane(width: w * 0.96, height: h * 0.96),
                                   materials: [faceMat])
        faceMesh.position = [0, 0, 0.005]
        addChild(faceMesh)
        // Face mesh is not in barChildren — animated separately via its fixed low alpha

        self.transform = Transform(matrix: wall.worldTransform)
        update(to: wall.highlightState, animated: false)
    }

    // MARK: - State update

    func update(to state: TrackedWall.HighlightState, animated: Bool = true) {
        let targetAlpha: Float
        let shouldPulse: Bool
        switch state {
        case .none:     targetAlpha = 0.00; shouldPulse = false
        case .partial:  targetAlpha = 0.35; shouldPulse = false
        case .good:     targetAlpha = 0.70; shouldPulse = false
        case .complete: targetAlpha = 1.00; shouldPulse = true
        }

        // Skip if already at target — avoids Task churn on unchanged walls
        guard abs(currentAlpha - targetAlpha) > 0.01 else { return }

        if animated {
            animateOpacity(to: targetAlpha)
        } else {
            opacityTask?.cancel()
            applyAlpha(targetAlpha)
        }

        if shouldPulse {
            startPulse()
            DispatchQueue.main.async { HapticService.shared.lightImpact() }
        }
    }

    // MARK: - Pulse

    private func startPulse() {
        let up   = Transform(scale: .init(repeating: 1.04))
        let down = Transform(scale: .init(repeating: 1.00))
        move(to: up,   relativeTo: parent, duration: 0.15, timingFunction: .easeOut)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.move(to: down, relativeTo: self?.parent, duration: 0.15, timingFunction: .easeIn)
        }
    }

    // MARK: - Opacity animation
    // Interpolates alpha across 12 steps. Uses cached barChildren to avoid
    // compactMap allocation on every step. Checks Task.isCancelled before
    // each step and before the sleep to exit promptly when superseded.

    private func animateOpacity(to targetAlpha: Float, duration: TimeInterval = 0.3) {
        opacityTask?.cancel()
        let fromAlpha = currentAlpha
        let steps     = 12
        let interval  = UInt64(duration / Double(steps) * 1_000_000_000)
        let bars      = barChildren   // capture by value — safe, [ModelEntity] is a struct array

        opacityTask = Task { @MainActor [weak self] in
            for step in 1...steps {
                guard !Task.isCancelled, let self else { return }
                let t     = Float(step) / Float(steps)
                let alpha = fromAlpha + (targetAlpha - fromAlpha) * t
                self.applyAlpha(alpha, to: bars)
                if step < steps {
                    try? await Task.sleep(nanoseconds: interval)
                }
            }
        }
    }

    // MARK: - Helpers

    private func applyAlpha(_ alpha: Float, to bars: [ModelEntity]? = nil) {
        currentAlpha = alpha
        let color    = Self.alphaColor(CGFloat(alpha))
        let targets  = bars ?? barChildren
        for model in targets {
            guard var mat = model.model?.materials.first as? UnlitMaterial else { continue }
            mat.color = .init(tint: color)
            model.model?.materials = [mat]
        }
    }

    private func addBar(size: SIMD3<Float>, pos: SIMD3<Float>) {
        let mat    = UnlitMaterial(color: Self.alphaColor(0.25))
        let entity = ModelEntity(mesh: .generateBox(size: size, cornerRadius: 0.008),
                                 materials: [mat])
        entity.position = pos
        addChild(entity)
        barChildren.append(entity)
    }
}
