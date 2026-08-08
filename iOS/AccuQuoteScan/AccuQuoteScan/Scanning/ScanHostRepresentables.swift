import SwiftUI
import RoomPlan
import ARKit
import SceneKit

// MARK: - UIViewRepresentable wrappers

/// Bridges the RoomPlan LiDAR scan into SwiftUI via a UIViewController.
/// RoomPlan's RoomCaptureView must live inside a UIViewController — it won't
/// render correctly as a bare UIViewRepresentable in a SwiftUI hierarchy.
struct LiDARHostRepresentable: UIViewControllerRepresentable {
    let coordinator: ScanCoordinator

    func makeUIViewController(context: Context) -> LiDARHostVC {
        LiDARHostVC(scanCoordinator: coordinator)
    }

    func updateUIViewController(_ vc: LiDARHostVC, context: Context) {}
}

final class LiDARHostVC: UIViewController {
    private let scanCoordinator: ScanCoordinator
    private var captureView: RoomCaptureView?

    init(scanCoordinator: ScanCoordinator) {
        self.scanCoordinator = scanCoordinator
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        // RoomCaptureView MUST be the root view — Metal won't render as a subview.
        let captureView = RoomCaptureView(frame: UIScreen.main.bounds)
        self.captureView = captureView
        scanCoordinator.setCaptureView(captureView)
        view = captureView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addDoneButton()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scanCoordinator.beginLiDARSession()
    }

    private func addDoneButton() {
        let btn = UIButton(type: .system)
        btn.setTitle("Done", for: .normal)
        btn.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        btn.setTitleColor(.white, for: .normal)
        btn.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        btn.layer.cornerRadius = 18
        if #available(iOS 15, *) {
            var config = UIButton.Configuration.plain()
            config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 18)
            btn.configuration = config
            btn.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attr in
                var a = attr; a.font = UIFont.systemFont(ofSize: 15, weight: .semibold); return a
            }
        } else {
            btn.contentEdgeInsets = UIEdgeInsets(top: 8, left: 18, bottom: 8, right: 18)
        }
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        view.addSubview(btn)
        NSLayoutConstraint.activate([
            btn.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            btn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])
    }

    @objc private func doneTapped() {
        scanCoordinator.stopScan()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        captureView?.removeFromSuperview()
        captureView = nil
    }
}

// Wraps ARSCNView in a UIViewController so we can start the session in viewDidAppear,
// guaranteeing the Metal layer has a valid drawable before session.run() is called.
final class ARHostVC: UIViewController {
    private let scanCoordinator: ScanCoordinator
    private var sceneView: ARSCNView?

    init(scanCoordinator: ScanCoordinator) {
        self.scanCoordinator = scanCoordinator
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let v = ARSCNView(frame: UIScreen.main.bounds)
        v.automaticallyUpdatesLighting = true
        v.session = scanCoordinator.arSession!
        sceneView = v
        view = v
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let session = scanCoordinator.arSession else { return }
        session.run(scanCoordinator.arConfiguration())
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView?.session.pause()
    }
}

struct ARHostRepresentable: UIViewControllerRepresentable {
    let coordinator: ScanCoordinator
    func makeUIViewController(context: Context) -> ARHostVC {
        ARHostVC(scanCoordinator: coordinator)
    }
    func updateUIViewController(_ vc: ARHostVC, context: Context) {}
}
