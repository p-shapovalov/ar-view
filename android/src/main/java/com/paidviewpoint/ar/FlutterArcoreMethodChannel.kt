package com.paidviewpoint.ar

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler

/**
 * Per-view method-channel surface between Dart and the native AR view.
 *
 * Direction              | Method          | Payload
 * -----------------------+-----------------+------------------------------------
 * Dart → Native          | loadModel       | { modelPath: String, fitMeters: Double }
 * Dart → Native          | removeNode      | { name: String }                   → Boolean
 * Dart → Native          | restoreNode     | { name: String }                   → Boolean
 * Dart → Native          | listNodes       | -                                   → List<String>
 * Native → Dart          | onPlaneTap      | { hitMatrix: FloatArray(16) }
 * Native → Dart          | onTrackingState | { trackingState: String, trackingFailureReason: String, hasPlanes: Boolean }
 * Native → Dart          | onNodeTap       | { name: String }                   (post-placement only)
 */
abstract class FlutterArcoreMethodChannel(messenger: BinaryMessenger, id: Int) : MethodCallHandler {
    private val methodChannel: MethodChannel = MethodChannel(messenger, "ar_$id")

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "loadModel" -> {
                val path = call.argument<String>("modelPath")
                if (path == null) {
                    result.error("INVALID_ARG", "modelPath is required", null)
                    return
                }
                val fitMeters = call.argument<Double>("fitMeters")?.toFloat() ?: 2.0f
                onLoadModel(path, fitMeters)
                result.success(null)
            }
            "removeNode" -> {
                val name = call.argument<String>("name")
                if (name == null) {
                    result.error("INVALID_ARG", "name is required", null)
                    return
                }
                result.success(onRemoveNode(name))
            }
            "restoreNode" -> {
                val name = call.argument<String>("name")
                if (name == null) {
                    result.error("INVALID_ARG", "name is required", null)
                    return
                }
                result.success(onRestoreNode(name))
            }
            "listNodes" -> result.success(onListNodes())
            else -> result.notImplemented()
        }
    }

    /** Implemented by [FlutterArcoreView] to receive `loadModel` requests. */
    protected abstract fun onLoadModel(modelPath: String, fitMeters: Float)
    protected abstract fun onRemoveNode(name: String): Boolean
    protected abstract fun onRestoreNode(name: String): Boolean
    protected abstract fun onListNodes(): List<String>

    fun onPlaneTap(hitMatrix: FloatArray) {
        val payload = HashMap<String, Any>(1)
        payload["hitMatrix"] = hitMatrix
        methodChannel.invokeMethod("onPlaneTap", payload)
    }

    /**
     * Tracking-state snapshot streamed once per ARCore frame. Enum names
     * pass through verbatim so the Dart side can localize and so we don't
     * have to bump the channel protocol when new ARCore reasons are added.
     */
    fun onTrackingState(trackingState: String, trackingFailureReason: String, hasPlanes: Boolean) {
        val payload = HashMap<String, Any>(3)
        payload["trackingState"] = trackingState
        payload["trackingFailureReason"] = trackingFailureReason
        payload["hasPlanes"] = hasPlanes
        methodChannel.invokeMethod("onTrackingState", payload)
    }

    fun onNodeTap(name: String) {
        methodChannel.invokeMethod("onNodeTap", hashMapOf<String, Any>("name" to name))
    }

    fun attachMethodChannel() {
        methodChannel.setMethodCallHandler(this)
    }
}
