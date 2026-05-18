import Flutter
import UIKit
import SceneKit
import GLTFKit2

/// Non-AR 3D model viewer. Custom pan + pinch handlers drive an explicit
/// camera, and the camera's distance is computed from the model's actual
/// world XY extents + the SCNView's bounds + the vertical FoV so the
/// model fills the screen on load and on orientation change — independent
/// of how tall or wide the source glb authored itself.
@available(iOS 13.0, *)
class Ios3DView: NSObject, FlutterPlatformView {
    private let sceneView: LayoutNotifyingSCNView
    private let channel: FlutterMethodChannel
    private var loadedAssetPath: String?

    private weak var cameraNode: SCNNode?
    // Post-autoFit world XY extents of the loaded model (Z-extent is
    // ignored — the camera looks down -Z, so depth doesn't constrain fit).
    private var modelExtentX: Float = 0
    private var modelExtentY: Float = 0
    private var hasModel = false
    // First user pinch pins the camera distance — after that we stop
    // auto-fitting on layout so we don't fight the user's zoom.
    private var userHasPinched = false

    private var panStartPosition: SCNVector3 = SCNVector3Zero
    private var pinchStartDistance: Float = 0

    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        binaryMessenger messenger: FlutterBinaryMessenger
    ) {
        self.sceneView = LayoutNotifyingSCNView(frame: frame)
        self.channel = FlutterMethodChannel(name: "three_d_\(viewId)", binaryMessenger: messenger)
        super.init()

        // No HDR shipped — let SceneKit synthesize a directional light if
        // none exists in the loaded scene, so PBR materials aren't
        // rendered pitch-black.
        sceneView.autoenablesDefaultLighting = true
        sceneView.backgroundColor = .black
        sceneView.scene = SCNScene()
        sceneView.onLayout = { [weak self] in self?.refitCameraIfNeeded() }

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        sceneView.addGestureRecognizer(pan)
        sceneView.addGestureRecognizer(pinch)

        channel.setMethodCallHandler { [weak self] call, result in
            self?.onMethodCall(call, result: result)
        }
    }

    func view() -> UIView { sceneView }

    private func onMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "loadModel":
            let args = call.arguments as? [String: Any] ?? [:]
            guard let modelPath = args["modelPath"] as? String else {
                result(FlutterError(code: "INVALID_ARG", message: "modelPath is required", details: nil))
                return
            }
            loadModel(assetPath: modelPath)
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func loadModel(assetPath: String) {
        if assetPath == loadedAssetPath { return }
        let key = FlutterDartProject.lookupKey(forAsset: assetPath)
        guard let bundlePath = Bundle.main.path(forResource: key, ofType: nil) else {
            NSLog("ar: model asset not found in bundle: \(assetPath) (key=\(key))")
            return
        }
        let url = URL(fileURLWithPath: bundlePath)
        GLTFAsset.load(with: url, options: [:]) { [weak self] _, status, asset, _, _ in
            guard let self = self else { return }
            guard status == .complete, let asset = asset else { return }
            DispatchQueue.main.async {
                // Pull the gltf's nodes into a fresh scene + container, the
                // same shape the AR path uses. Reassigning `SCNScene` from
                // GLTFKit2 leaves SceneKit's defaultCameraController in an
                // unframed state (= black screen); building our own
                // hierarchy with an explicit camera makes framing
                // deterministic and lets gestures drive a known camera.
                let gltfScene = SCNScene(gltfAsset: asset)
                let scene = SCNScene()
                let container = SCNNode()
                gltfScene.rootNode.childNodes.forEach { container.addChildNode($0) }
                // autoFit normalises the *largest* extent to fitMeters and
                // re-pivots so the centroid sits at world origin. Gesture
                // sensitivities downstream stay tuned to that constant.
                container.autoFit(to: Ios3DView.fitMeters)
                scene.rootNode.addChildNode(container)

                let cameraNode = SCNNode()
                let camera = SCNCamera()
                camera.zNear = 0.01
                camera.zFar = 1000
                camera.fieldOfView = 60
                // Pin FoV to the vertical axis so the same FoV value yields
                // a stable vertical framing across orientations; the
                // horizontal FoV scales with aspect from there.
                camera.projectionDirection = .vertical
                cameraNode.camera = camera
                cameraNode.position = SCNVector3(0, 0, Ios3DView.fitMeters * 2.5)
                scene.rootNode.addChildNode(cameraNode)

                self.sceneView.scene = scene
                self.sceneView.pointOfView = cameraNode
                self.cameraNode = cameraNode

                // Capture the model's world XY extents post-autoFit so
                // refitCameraIfNeeded() can dolly the camera to fit them.
                let (minV, maxV) = container.boundingBox
                let s = container.scale.x
                self.modelExtentX = (maxV.x - minV.x) * s
                self.modelExtentY = (maxV.y - minV.y) * s
                self.hasModel = true
                self.userHasPinched = false
                self.loadedAssetPath = assetPath

                self.refitCameraIfNeeded()
            }
        }
    }

    // MARK: - Fit-to-screen

    /// Place the camera at the distance that makes the model's larger
    /// projected axis fill `fillRatio` of the viewport. Skipped after the
    /// first user pinch so we don't reset their zoom on subsequent layouts.
    private func refitCameraIfNeeded() {
        guard hasModel, !userHasPinched, let cam = cameraNode else { return }
        let w = Float(sceneView.bounds.width)
        let h = Float(sceneView.bounds.height)
        guard w > 0, h > 0 else { return }
        let aspect = w / h
        let fovV = Float(cam.camera?.fieldOfView ?? 60) * .pi / 180
        let halfV = tanf(fovV / 2)
        let halfH = halfV * aspect
        // Distance required by each axis to make the model exactly fill
        // that axis; max() picks the constraining axis (taller-than-wide
        // model → vertical constrains; wider-than-tall → horizontal).
        let dByY = modelExtentY / (2 * halfV)
        let dByX = modelExtentX / (2 * halfH)
        let d = max(dByX, dByY) / Ios3DView.fillRatio
        cam.position = SCNVector3(cam.position.x, cam.position.y, d)
    }

    // MARK: - Gestures

    /// Pixels per world-meter at the camera's current depth, on the
    /// vertical axis. Used to translate finger movement into camera offset
    /// so a drag tracks the model 1:1 on screen at any zoom level.
    private func pixelsPerMeter(forCamera cam: SCNNode) -> Float {
        let distance = max(cam.position.z, 0.01)
        let fovV = Float(cam.camera?.fieldOfView ?? 60) * .pi / 180
        let viewportWorldHeight = 2 * distance * tanf(fovV / 2)
        return Float(sceneView.bounds.height) / viewportWorldHeight
    }

    @objc private func handlePan(_ r: UIPanGestureRecognizer) {
        guard let cam = cameraNode else { return }
        switch r.state {
        case .began:
            panStartPosition = cam.position
        case .changed:
            let t = r.translation(in: sceneView)
            let pxPerMeter = pixelsPerMeter(forCamera: cam)
            // Move camera opposite to finger so the model appears to
            // follow the drag. Screen Y points down, world Y points up.
            cam.position = SCNVector3(
                panStartPosition.x - Float(t.x) / pxPerMeter,
                panStartPosition.y + Float(t.y) / pxPerMeter,
                panStartPosition.z,
            )
        default: break
        }
    }

    @objc private func handlePinch(_ r: UIPinchGestureRecognizer) {
        guard let cam = cameraNode else { return }
        switch r.state {
        case .began:
            userHasPinched = true
            pinchStartDistance = cam.position.z
        case .changed:
            // Pinch out (scale > 1) → bring camera closer → larger model.
            let proposed = pinchStartDistance / Float(r.scale)
            let clamped = proposed.clamped(to: Ios3DView.minDistance...Ios3DView.maxDistance)
            cam.position = SCNVector3(cam.position.x, cam.position.y, clamped)
        default: break
        }
    }

    private static let fitMeters: Float = 1.5
    private static let fillRatio: Float = 0.85
    private static let minDistance: Float = fitMeters * 0.4
    private static let maxDistance: Float = fitMeters * 20.0
}

@available(iOS 13.0, *)
extension Ios3DView: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        return true
    }
}

/// SCNView subclass that surfaces a layout callback. Used to re-run the
/// fit-to-screen logic when Flutter assigns the view's real size after
/// `init(frame:)` and on subsequent bounds changes (e.g., orientation).
@available(iOS 13.0, *)
private class LayoutNotifyingSCNView: SCNView {
    var onLayout: (() -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}
