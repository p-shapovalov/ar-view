package com.paidviewpoint.ar

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler

/**
 * Per-view method-channel surface between Dart and the native 3D view.
 *
 * Direction      | Method     | Payload
 * ---------------+------------+----------------------------------------
 * Dart → Native  | loadModel  | { modelPath: String }
 *
 * No back-channel — gestures and autofit are handled natively by
 * SceneView, so there's nothing per-frame to surface.
 */
abstract class Flutter3DMethodChannel(messenger: BinaryMessenger, id: Int) : MethodCallHandler {
    private val methodChannel: MethodChannel = MethodChannel(messenger, "three_d_$id")

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "loadModel" -> {
                val path = call.argument<String>("modelPath")
                if (path == null) {
                    result.error("INVALID_ARG", "modelPath is required", null)
                    return
                }
                onLoadModel(path)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    protected abstract fun onLoadModel(modelPath: String)

    fun attachMethodChannel() {
        methodChannel.setMethodCallHandler(this)
    }
}
