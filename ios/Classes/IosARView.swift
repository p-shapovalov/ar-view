import Flutter
import UIKit
import ARKit
import GLTFKit2
import simd

/// Native AR view: renders glb models in the same SceneKit context as
/// ARKit's camera feed, eliminating the Dart-side `flutter_scene`
/// CustomPaint overlay (and the per-frame projection/view-matrix stream
/// that fed it). Matches the Android `FlutterArcoreView` contract:
///
///   Dart → Native:  loadModel(modelPath, fitMeters)
///   Native → Dart:  onPlaneTap(hitMatrix)
///                   onTrackingState(trackingState, trackingFailureReason, hasPlanes)
@available(iOS 13.0, *)
class IosARView: NSObject, FlutterPlatformView, ARSCNViewDelegate, ARSessionDelegate {
    private let sceneView: ARSCNView
    private let channel: FlutterMethodChannel
    private let modelBuilder = ArModelBuilder()
    private var trackedPlanes = [UUID: (SCNNode, SCNNode)]()

    // Loaded glb root — set asynchronously by `loadModel`. The actual
    // node attached to an anchor is a deep clone so the template can be
    // reused across re-place flows.
    private var modelTemplate: SCNNode?
    private var loadedAssetPath: String?
    private var fitMeters: Float = 2.0
    // The ARAnchor we created for the model; tracked so we can attach the
    // model in `renderer(_:didAdd:for:)` once ARKit instantiates its node.
    private var placedAnchor: ARAnchor?
    // The placed model node — modified by pinch/pan gesture handlers to
    // let the user fine-tune size and position within the anchor's local
    // frame (anchor's +X = wall horizontal, +Y = world up, +Z = wall out).
    private weak var placedModelNode: SCNNode?
    // Scoped to the current placedModelNode — cleared whenever a fresh
    // clone is attached so refs into a defunct clone can't dangle.
    private var removedNodes = DetachedSubtreeStore()
    // Auto-fit transform captured at placement time so per-gesture deltas
    // can be applied on top without compounding.
    private var modelBaseScale: SCNVector3 = SCNVector3(1, 1, 1)
    private var modelBasePosition: SCNVector3 = SCNVector3Zero
    private var userScale: Float = 1.0
    private var userOffset: SCNVector3 = SCNVector3Zero
    private var pinchSnapshot: Float = 1.0
    private var panSnapshot: SCNVector3 = SCNVector3Zero

    // De-duplicate the per-frame onTrackingState push so we only hop the
    // channel when something actually changed.
    private var lastTrackingState: String?
    private var lastFailureReason: String?
    private var lastHasPlanes: Bool?

    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        binaryMessenger messenger: FlutterBinaryMessenger
    ) {
        self.sceneView = ARSCNView(frame: frame)
        self.channel = FlutterMethodChannel(name: "ar_\(viewId)", binaryMessenger: messenger)
        super.init()

        sceneView.delegate = self
        sceneView.session.delegate = self
        // PBR materials from glb need an environment probe to look right;
        // ARKit can synthesise one from the camera feed automatically.
        sceneView.automaticallyUpdatesLighting = true

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.vertical]
        config.environmentTexturing = .automatic
        sceneView.session.run(config)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        sceneView.addGestureRecognizer(tap)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pinch.delegate = self
        pan.delegate = self
        pan.maximumNumberOfTouches = 1
        sceneView.addGestureRecognizer(pinch)
        sceneView.addGestureRecognizer(pan)

        addCoachingOverlay()

        channel.setMethodCallHandler { [weak self] call, result in
            self?.onMethodCall(call, result: result)
        }
    }

    func view() -> UIView { sceneView }

    // MARK: - Method channel

    private func onMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "loadModel":
            let args = call.arguments as? [String: Any] ?? [:]
            guard let modelPath = args["modelPath"] as? String else {
                result(FlutterError(code: "INVALID_ARG", message: "modelPath is required", details: nil))
                return
            }
            let fit = (args["fitMeters"] as? Double).map { Float($0) } ?? 2.0
            loadModel(assetPath: modelPath, fitMeters: fit)
            result(nil)
        case "removeNode":
            let args = call.arguments as? [String: Any] ?? [:]
            guard let name = args["name"] as? String else {
                result(FlutterError(code: "INVALID_ARG", message: "name is required", details: nil))
                return
            }
            result(removeNode(named: name))
        case "restoreNode":
            let args = call.arguments as? [String: Any] ?? [:]
            guard let name = args["name"] as? String else {
                result(FlutterError(code: "INVALID_ARG", message: "name is required", details: nil))
                return
            }
            result(restoreNode(named: name))
        case "listNodes":
            result(listNodeNames())
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Model loading

    private func loadModel(assetPath: String, fitMeters: Float) {
        // Re-attach (background→foreground, route re-entry) fires loadModel
        // again with the same path; skip the GLTFAsset re-parse if we
        // already have the template cached.
        if assetPath == loadedAssetPath && modelTemplate != nil {
            self.fitMeters = fitMeters
            return
        }
        let key = FlutterDartProject.lookupKey(forAsset: assetPath)
        guard let bundlePath = Bundle.main.path(forResource: key, ofType: nil) else {
            NSLog("ar: model asset not found in bundle: \(assetPath) (key=\(key))")
            return
        }
        let url = URL(fileURLWithPath: bundlePath)
        self.fitMeters = fitMeters
        GLTFAsset.load(with: url, options: [:]) { [weak self] _, status, asset, _, _ in
            guard let self = self else { return }
            guard status == .complete, let asset = asset else { return }
            let scene = SCNScene(gltfAsset: asset)
            let container = SCNNode()
            scene.rootNode.childNodes.forEach { container.addChildNode($0) }
            container.autoFit(to: fitMeters)
            DispatchQueue.main.async {
                self.modelTemplate = container
                self.loadedAssetPath = assetPath
            }
        }
    }

    // MARK: - Tap → anchor placement

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        let location = recognizer.location(in: sceneView)
        if placedAnchor != nil {
            handleNodeTap(at: location)
            return
        }
        guard modelTemplate != nil else { return }
        guard let query = sceneView.raycastQuery(
            from: location,
            allowing: .existingPlaneGeometry,
            alignment: .vertical
        ) else { return }
        guard let hit = sceneView.session.raycast(query).first else { return }

        let corrected = wallMountedTransform(
            hitTransform: hit.worldTransform,
            cameraTransform: sceneView.session.currentFrame?.camera.transform
        )
        let anchor = ARAnchor(transform: corrected)
        sceneView.session.add(anchor: anchor)
        placedAnchor = anchor

        // Hide the wall-plane visualizers now that the model is placed —
        // they served as a "tap here" affordance and clutter the scene
        // afterwards. New planes detected post-placement are already
        // suppressed by the `placedAnchor == nil` guard in `didAdd`.
        trackedPlanes.values.forEach { $0.1.removeFromParentNode() }

        channel.invokeMethod("onPlaneTap", arguments: ["hitMatrix": serializeMatrix(corrected)])
    }

    @objc private func handlePinch(_ r: UIPinchGestureRecognizer) {
        guard let node = placedModelNode else { return }
        switch r.state {
        case .began:
            pinchSnapshot = userScale
        case .changed:
            let proposed = pinchSnapshot * Float(r.scale)
            userScale = proposed.clamped(to: IosARView.minScale...IosARView.maxScale)
            node.scale = SCNVector3(
                modelBaseScale.x * userScale,
                modelBaseScale.y * userScale,
                modelBaseScale.z * userScale,
            )
        default: break
        }
    }

    @objc private func handlePan(_ r: UIPanGestureRecognizer) {
        guard let node = placedModelNode, r.numberOfTouches == 1 else { return }
        switch r.state {
        case .began:
            panSnapshot = userOffset
        case .changed:
            let translation = r.translation(in: sceneView)
            // Pixels → anchor-local meters. fitMeters across the viewport
            // width gives "drag the model across the wall at roughly
            // screen speed".
            let pxPerMeter = Float(sceneView.bounds.width) / fitMeters.clamped(to: 0.01...Float.greatestFiniteMagnitude)
            userOffset = SCNVector3(
                panSnapshot.x + Float(translation.x) / pxPerMeter,
                panSnapshot.y - Float(translation.y) / pxPerMeter, // screen Y inverted
                0,
            )
            node.position = SCNVector3(
                modelBasePosition.x + userOffset.x,
                modelBasePosition.y + userOffset.y,
                modelBasePosition.z,
            )
        default: break
        }
    }

    private static let minScale: Float = 0.25
    private static let maxScale: Float = 4.0

    /// Build a corrected anchor pose so the model:
    ///   - has +Y aligned with world up,
    ///   - has +Z pointing out of the wall toward the camera.
    /// ARKit vertical-plane hits report their pose with +Y as the outward
    /// wall normal, so we rebuild the basis explicitly from world up + the
    /// chosen forward direction.
    private func wallMountedTransform(
        hitTransform: simd_float4x4,
        cameraTransform: simd_float4x4?
    ) -> simd_float4x4 {
        let yAxis = simd_float3(hitTransform.columns.1.x, hitTransform.columns.1.y, hitTransform.columns.1.z)
        let normal = simd_normalize(yAxis)
        let hitPos = simd_float3(hitTransform.columns.3.x, hitTransform.columns.3.y, hitTransform.columns.3.z)
        let camPos = cameraTransform.map {
            simd_float3($0.columns.3.x, $0.columns.3.y, $0.columns.3.z)
        } ?? simd_float3(0, 0, 0)
        let toCamera = simd_normalize(camPos - hitPos)
        let forward = (simd_dot(normal, toCamera) >= 0) ? normal : -normal
        let worldUp = simd_float3(0, 1, 0)
        let right = simd_normalize(simd_cross(worldUp, forward))
        let up = simd_cross(forward, right)
        var m = matrix_identity_float4x4
        m.columns.0 = simd_float4(right.x, right.y, right.z, 0)
        m.columns.1 = simd_float4(up.x, up.y, up.z, 0)
        m.columns.2 = simd_float4(forward.x, forward.y, forward.z, 0)
        m.columns.3 = simd_float4(hitPos.x, hitPos.y, hitPos.z, 1)
        return m
    }

    // MARK: - Node remove / restore / tap

    private func handleNodeTap(at point: CGPoint) {
        guard let root = placedModelNode else { return }
        // Scope the hit-test to the placed model — taps on the AR camera
        // feed shouldn't surface unrelated SceneKit world nodes or the
        // plane visualizers.
        let hits = sceneView.hitTest(point, options: [
            .rootNode: root,
            .searchMode: SCNHitTestSearchMode.closest.rawValue,
        ])
        guard let name = hits.first?.node.firstNamedAncestorName(stoppingAt: root) else { return }
        NSLog("ar: AR node tap → \(name)")
        channel.invokeMethod("onNodeTap", arguments: ["name": name])
    }

    private func removeNode(named name: String) -> Bool {
        guard let root = placedModelNode else { return false }
        return removedNodes.remove(named: name, from: root)
    }

    private func restoreNode(named name: String) -> Bool {
        return removedNodes.restore(named: name)
    }

    private func listNodeNames() -> [String] {
        return placedModelNode?.namedDescendants() ?? []
    }

    // MARK: - ARSCNViewDelegate (plane viz + model attachment)

    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        if anchor === placedAnchor, let template = modelTemplate {
            // Clone so the template stays reusable (e.g. on reset). The
            // anchor's node already carries the corrected world transform,
            // so the model is added with identity local transform; pinch
            // and pan handlers modify it directly via [placedModelNode].
            let modelNode = template.clone()
            node.addChildNode(modelNode)
            placedModelNode = modelNode
            // Drop refs into the previous (defunct) clone.
            removedNodes.clear()
            modelBaseScale = modelNode.scale
            modelBasePosition = modelNode.position
            userScale = 1.0
            userOffset = SCNVector3Zero
            return
        }
        if let planeAnchor = anchor as? ARPlaneAnchor {
            let plane = modelBuilder.makePlane(anchor: planeAnchor)
            trackedPlanes[anchor.identifier] = (node, plane)
            if placedAnchor == nil { node.addChildNode(plane) }
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        if let planeAnchor = anchor as? ARPlaneAnchor,
           let pair = trackedPlanes[anchor.identifier] {
            modelBuilder.updatePlaneNode(planeNode: pair.1, anchor: planeAnchor)
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        trackedPlanes.removeValue(forKey: anchor.identifier)
    }

    // MARK: - ARSessionDelegate (tracking state)

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let state = trackingStateName(frame.camera.trackingState)
        let reason = trackingFailureReasonName(frame.camera.trackingState)
        let hasPlanes = frame.anchors.contains {
            ($0 as? ARPlaneAnchor)?.alignment == .vertical
        }
        if state != lastTrackingState || reason != lastFailureReason || hasPlanes != lastHasPlanes {
            lastTrackingState = state
            lastFailureReason = reason
            lastHasPlanes = hasPlanes
            channel.invokeMethod("onTrackingState", arguments: [
                "trackingState": state,
                "trackingFailureReason": reason,
                "hasPlanes": hasPlanes,
            ])
        }
    }

    // MARK: - Tracking-state name mapping (matches ARCore enum names so
    // the Dart side can use the same parser for both platforms)

    private func trackingStateName(_ state: ARCamera.TrackingState) -> String {
        switch state {
        case .normal: return "TRACKING"
        case .notAvailable: return "STOPPED"
        case .limited: return "PAUSED"
        }
    }

    private func trackingFailureReasonName(_ state: ARCamera.TrackingState) -> String {
        guard case .limited(let reason) = state else { return "NONE" }
        switch reason {
        case .initializing: return "NONE"
        case .relocalizing: return "BAD_STATE"
        case .excessiveMotion: return "EXCESSIVE_MOTION"
        case .insufficientFeatures: return "INSUFFICIENT_FEATURES"
        @unknown default: return "UNKNOWN"
        }
    }
}

// MARK: - Coaching overlay

// MARK: - Gesture delegate (allow pinch + pan simultaneously)

@available(iOS 13.0, *)
extension IosARView: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        return true
    }
}

@available(iOS 13.0, *)
extension IosARView: ARCoachingOverlayViewDelegate {
    func addCoachingOverlay() {
        // Re-attach paths can hit this more than once; remove any prior
        // overlay so they don't stack and accumulate sessions.
        sceneView.subviews
            .compactMap { $0 as? ARCoachingOverlayView }
            .forEach { $0.removeFromSuperview() }
        let coachingView = ARCoachingOverlayView(frame: sceneView.frame)
        coachingView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        coachingView.goal = .verticalPlane
        coachingView.session = sceneView.session
        coachingView.delegate = self
        coachingView.setActive(true, animated: true)
        sceneView.addSubview(coachingView)
    }
}
