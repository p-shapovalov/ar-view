import Flutter
import UIKit
import ARKit

@available(iOS 13.0, *)
public class SwiftArPlugin: NSObject, FlutterPlugin {
    static var channel: FlutterMethodChannel? = nil
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        channel = FlutterMethodChannel(name: "ar", binaryMessenger: registrar.messenger())
        let instance = SwiftArPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel!)
      
        let factory = IosARViewFactory(messenger: registrar.messenger())
        registrar.register(factory, withId: "com.paidviewpoint.ar")
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isAvailable":
            result(ARConfiguration.isSupported)
            break
        default:
            break
        }
    }
}
