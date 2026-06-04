import SwiftUI
import RoomPlan
import ARKit

// MARK: - ScanViewControllerBridge
// UIViewControllerRepresentable that embeds RoomCaptureView in SwiftUI.

struct ScanViewControllerBridge: UIViewControllerRepresentable {
    @ObservedObject var sessionManager: ScanSessionManager

    func makeUIViewController(context: Context) -> ScanViewController {
        ScanViewController(sessionManager: sessionManager)
    }

    func updateUIViewController(_ vc: ScanViewController, context: Context) {}
}

// MARK: - ScanViewController
// @MainActor matches the isolation of ScanSessionManager — all calls to the
// manager are actor-safe without needing async/await wrappers.

@MainActor
final class ScanViewController: UIViewController {
    private let sessionManager: ScanSessionManager
    private var roomCaptureView: RoomCaptureView?
    private var coachingOverlay: ARCoachingOverlayView?

    init(sessionManager: ScanSessionManager) {
        self.sessionManager = sessionManager
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let captureView = sessionManager.makeRoomCaptureView()
        captureView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(captureView)

        NSLayoutConstraint.activate([
            captureView.topAnchor.constraint(equalTo: view.topAnchor),
            captureView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            captureView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            captureView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        self.roomCaptureView = captureView
        setupCoachingOverlay(for: captureView)
    }

    // MARK: - ARCoachingOverlayView (Fix #1)
    // Goal is .anyPlane so coaching continues until floor/wall planes are established,
    // not just basic motion tracking. Delegate hides/shows our custom HUD so the two
    // systems never overlap during initialisation.

    private func setupCoachingOverlay(for captureView: RoomCaptureView) {
        let overlay = ARCoachingOverlayView()
        overlay.session = captureView.captureSession.arSession
        overlay.goal = .anyPlane
        overlay.activatesAutomatically = true
        overlay.delegate = self
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlay)

        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        self.coachingOverlay = overlay
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        sessionManager.startScan()
    }

    // Fix #15 / #9 — stop synchronously before reset to cut off in-flight callbacks.
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionManager.stopCapture()   // synchronous session stop on MainActor
        sessionManager.reset()         // full state reset — safe because stopCapture() already cleared delegates
    }
}

// MARK: - ARCoachingOverlayViewDelegate (Fix #7)
// Hides the scan HUD while coaching is active so the two systems don't compete.

extension ScanViewController: ARCoachingOverlayViewDelegate {

    func coachingOverlayViewWillActivate(_ coachingOverlayView: ARCoachingOverlayView) {
        sessionManager.isCoachingActive = true
    }

    func coachingOverlayViewDidDeactivate(_ coachingOverlayView: ARCoachingOverlayView) {
        sessionManager.isCoachingActive = false
    }

    func coachingOverlayViewDidRequestSessionReset(_ coachingOverlayView: ARCoachingOverlayView) {
        // User tapped "Start Over" in the coaching overlay — reset and restart
        sessionManager.reset()
        sessionManager.startScan()
    }
}
