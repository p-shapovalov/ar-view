package com.paidviewpoint.ar

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler

/**
 * Per-view method-channel surface between Dart and the native 3D view.
 *
 * Direction      | Method       | Payload
 * ---------------+--------------+----------------------------------------
 * Dart → Native  | loadModel    | { modelPath: String }
 * Dart → Native  | removeNode   | { name: String }              → Boolean
 * Dart → Native  | restoreNode  | { name: String }              → Boolean
 * Dart → Native  | listNodes    | -                              → List<String>
 * Native → Dart  | onNodeTap    | { name: String }
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

    protected abstract fun onLoadModel(modelPath: String)
    protected abstract fun onRemoveNode(name: String): Boolean
    protected abstract fun onRestoreNode(name: String): Boolean
    protected abstract fun onListNodes(): List<String>

    fun onNodeTap(name: String) {
        methodChannel.invokeMethod("onNodeTap", hashMapOf<String, Any>("name" to name))
    }

    fun attachMethodChannel() {
        methodChannel.setMethodCallHandler(this)
    }
}
