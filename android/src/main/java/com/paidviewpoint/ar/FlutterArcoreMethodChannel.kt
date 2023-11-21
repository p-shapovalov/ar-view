package com.paidviewpoint.ar

import android.opengl.Matrix
import com.google.ar.core.HitResult
import com.google.ar.core.Plane
import com.google.ar.core.Pose
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler

//class FlutterArCoreImage(map: HashMap<String, *>) {
//    val width: Int = map["width"] as Int
//    val height: Int = map["height"] as Int
//    val bytes: ByteArray = map["bytes"] as ByteArray
//    val transformation: FloatArray = (map["transformation"] as DoubleArray).map { it.toFloat() }.toFloatArray()
//}

abstract class FlutterArcoreMethodChannel(messenger: BinaryMessenger, id: Int) : MethodCallHandler {
    private val methodChannel: MethodChannel =
        MethodChannel(messenger, "ar_$id")

//    private val eventChannel = EventChannel(messenger, "ar_stream_$id")

    override fun onMethodCall(methodCall: MethodCall, result: MethodChannel.Result) {
//        if (methodCall.method == "add_image") {
//            val map = methodCall.arguments as HashMap<String, Any>
//            val image = FlutterArCoreImage(map)
//            addImage(image)
//        }
        result.success(null)
    }

//    abstract fun addImage(image: FlutterArCoreImage)

    fun onFrame(projectionMatrix: FloatArray, viewMatrix: FloatArray, hasPlanes: Boolean) {
//        val modelMatrix = FloatArray(16)
//        Matrix.setRotateEulerM(modelMatrix, 0, 0f, 0f, 0f)
//
//        val modelViewMatrix = FloatArray(16)
//        Matrix.multiplyMM(modelViewMatrix, 0, viewMatrix, 0, modelMatrix, 0)
//        val modelViewProjectionMatrix = FloatArray(16)
//        Matrix.multiplyMM(modelViewProjectionMatrix, 0, projectionMatrix, 0, modelViewMatrix, 0)

        val frameResult = HashMap<String, Any>()
        frameResult["projectionMatrix"] = projectionMatrix // Type plane
        frameResult["viewMatrix"] = viewMatrix // Type p
        frameResult["hasPlanes"] = hasPlanes// lane

        methodChannel.invokeMethod("onFrame", frameResult)
    }

    fun onPlaneTap(hitPose: Pose) {
        val hitMatrix = FloatArray(16)
        hitPose.toMatrix(hitMatrix, 0)

        val serializedHitResult = HashMap<String, Any>()
        serializedHitResult["hitMatrix"] = hitMatrix

        methodChannel.invokeMethod("onPlaneTap", serializedHitResult)
    }

    fun init() {
        methodChannel.setMethodCallHandler(this)
    }
}