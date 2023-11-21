import Flutter
import UIKit
import Foundation
import ARKit
import Combine


@available(iOS 13.0, *)
class IosARView: NSObject, FlutterPlatformView, ARSCNViewDelegate, UIGestureRecognizerDelegate, ARSessionDelegate {
    let sceneView: ARSCNView
    let sessionManagerChannel: FlutterMethodChannel
    private var trackedPlanes = [UUID: (SCNNode, SCNNode)]()
    let modelBuilder = ArModelBuilder()
    
    var anchor: ARAnchor?
    
    var cancellableCollection = Set<AnyCancellable>() //Used to store all cancellables in (needed for working with Futures)
    
    
    private var configuration: ARWorldTrackingConfiguration!
    private var tappedPlaneAnchorAlignment = ARPlaneAnchor.Alignment.vertical // default alignment
    
    private var panStartLocation: CGPoint?
    private var panCurrentLocation: CGPoint?
    private var panCurrentVelocity: CGPoint?
    private var panCurrentTranslation: CGPoint?
    private var rotationStartLocation: CGPoint?
    private var rotation: CGFloat?
    private var rotationVelocity: CGFloat?
    private var panningNode: SCNNode?
    private var panningNodeCurrentWorldLocation: SCNVector3?

    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        binaryMessenger messenger: FlutterBinaryMessenger
    ) {
        self.sceneView = ARSCNView(frame: frame)
        
        self.sessionManagerChannel = FlutterMethodChannel(name: "ar_\(viewId)", binaryMessenger: messenger)
        super.init()

        let configuration = ARWorldTrackingConfiguration() // Create default configuration before initializeARView is called
        self.sceneView.delegate = self
        self.sceneView.session.run(configuration)
        self.sceneView.session.delegate = self

        self.sessionManagerChannel.setMethodCallHandler(self.onSessionMethodCalled)
        initializeARView()
    }

    func view() -> UIView {
        return self.sceneView
    }

    func onDispose(_ result:FlutterResult) {
                sceneView.session.pause()
                self.sessionManagerChannel.setMethodCallHandler(nil)
                result(nil)
            }

    func onSessionMethodCalled(_ call :FlutterMethodCall, _ result:FlutterResult) {
//        let arguments = call.arguments as? Dictionary<String, Any>

        switch call.method {
            case "dispose":
                onDispose(result)
                result(nil)
                break
            default:
                result(FlutterMethodNotImplemented)
                break
        }
    }

    func initializeARView(){
        // Set plane detection configuration
        self.configuration = ARWorldTrackingConfiguration()
        if(self.anchor != nil) {
            
            configuration.planeDetection = []
            for plane in trackedPlanes.values {
                plane.1.removeFromParentNode()
            }
            
            self.sceneView.gestureRecognizers?.removeAll()
            
        } else  {
            configuration.planeDetection = [.vertical]

        
            // Set plane rendering options
            for plane in trackedPlanes.values {
                plane.0.addChildNode(plane.1)
            }
        

        // Set debug options
//        self.sceneView.debugOptions = ARSCNDebugOptions()
        
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tapGestureRecognizer.delegate = self
        self.sceneView.gestureRecognizers?.append(tapGestureRecognizer)
            addCoachingOverlay()
        }
        // Update session configuration
        self.sceneView.session.run(configuration)
    }

    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        
        if let planeAnchor = anchor as? ARPlaneAnchor{
            let plane = modelBuilder.makePlane(anchor: planeAnchor)
            trackedPlanes[anchor.identifier] = (node, plane)
            if (self.anchor == nil) {
//                removeCoachingOverlay()
                node.addChildNode(plane)
            }
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        
        if let planeAnchor = anchor as? ARPlaneAnchor, let plane = trackedPlanes[anchor.identifier] {
            modelBuilder.updatePlaneNode(planeNode: plane.1, anchor: planeAnchor)
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        trackedPlanes.removeValue(forKey: anchor.identifier)
    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let orientation = UIApplication.shared.windows.first?.windowScene?.interfaceOrientation ?? UIInterfaceOrientation.portrait   
        let serializedFrameResult = serializeFrame(frame.camera.viewMatrix(for: orientation), frame.camera.projectionMatrix(for: orientation, viewportSize: sceneView.bounds.size, zNear: 0.01, zFar: 1000))
        
        self.sessionManagerChannel.invokeMethod("onFrame", arguments: serializedFrameResult)

    }
    
    @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard let sceneView = recognizer.view as? ARSCNView else {
            return
        }
        let touchLocation = recognizer.location(in: sceneView)
            
        let planeTypes = ARHitTestResult.ResultType([.existingPlaneUsingGeometry])
        
        let planeAndPointHitResults = sceneView.hitTest(touchLocation, types: planeTypes)
        
        if planeAndPointHitResults.count > 0, let hitAnchor = planeAndPointHitResults.first?.anchor as? ARPlaneAnchor {
            self.tappedPlaneAnchorAlignment = hitAnchor.alignment
        }
        
        let hitResult = planeAndPointHitResults.first
    
        if (hitResult != nil) {
            self.anchor = hitResult!.anchor
            self.sessionManagerChannel.invokeMethod("onPlaneTap", arguments: serializeHitResult(hitResult!.worldTransform))
            initializeARView()
        }
    }
}

// ---------------------- ARCoachingOverlayViewDelegate ---------------------------------------


@available(iOS 13.0, *)
extension IosARView: ARCoachingOverlayViewDelegate {
  func addCoachingOverlay() {
    let goal = ARCoachingOverlayView.Goal.verticalPlane
    let coachingView = ARCoachingOverlayView(frame: self.sceneView.frame)

    coachingView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

    removeCoachingOverlay()

    sceneView.addSubview(coachingView)

    coachingView.goal = goal
    coachingView.session = self.sceneView.session
    coachingView.delegate = self
    coachingView.setActive(true, animated: true)
  }

  func removeCoachingOverlay() {
    if let view = sceneView.subviews.first(where: {$0 is ARCoachingOverlayView}) {
      view.removeFromSuperview()
    }
  }
}
