import Flutter
import UIKit
import SceneKit
import GLTFKit2

/// Non-AR 3D model viewer. Built-in `SCNView.allowsCameraControl` gives
/// orbit / pan / pinch-zoom gestures with no additional code; GLTFKit2
/// loads the glb on demand.
@available(iOS 13.0, *)
class Ios3DView: NSObject, FlutterPlatformView {
    private let sceneView: SCNView
    private let channel: FlutterMethodChannel
    private var loadedAssetPath: String?

    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        binaryMessenger messenger: FlutterBinaryMessenger
    ) {
        self.sceneView = SCNView(frame: frame)
        self.channel = FlutterMethodChannel(name: "three_d_\(viewId)", binaryMessenger: messenger)
        super.init()

        // Built-in gesture handling. `.pan` makes a single-finger drag
        // translate the camera in the screen plane instead of orbiting
        // the scene; pinch keeps its dolly-zoom behavior regardless of
        // mode. Net interaction: move + zoom, no rotation.
        sceneView.allowsCameraControl = true
        sceneView.defaultCameraController.interactionMode = .pan
        // No HDR shipped — let SceneKit synthesize a directional light if
        // none exists in the loaded scene, so PBR materials aren't
        // rendered pitch-black.
        sceneView.autoenablesDefaultLighting = true
        sceneView.backgroundColor = .black
        sceneView.scene = SCNScene()

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
                let scene = SCNScene(gltfAsset: asset)
                // Normalise the model's largest extent to a fixed value
                // BEFORE assigning the scene, so `allowsCameraControl`'s
                // default camera framing + the controller's gesture
                // speeds are tuned for the same on-screen size regardless
                // of the source glb's intrinsic scale. Matches the
                // Android side's `scaleToUnits = FIT_METERS`.
                scene.rootNode.autoFit(to: Ios3DView.fitMeters)
                self.sceneView.scene = scene
                self.loadedAssetPath = assetPath
            }
        }
    }

    private static let fitMeters: Float = 1.5
}
