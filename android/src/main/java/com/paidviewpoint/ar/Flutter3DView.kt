package com.paidviewpoint.ar

import android.content.Context
import android.view.View
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.LifecycleOwner
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.platform.PlatformView
import io.github.sceneview.SceneView
import io.github.sceneview.gesture.CameraGestureDetector
import io.github.sceneview.model.model
import io.github.sceneview.node.ModelNode
import io.github.sceneview.rememberEngine
import io.github.sceneview.rememberMaterialLoader
import io.github.sceneview.rememberModelLoader

/**
 * Non-AR 3D model viewer. Hosts SceneView's `SceneView` composable inside
 * a [ComposePlatformHost]. Pinch dollies the camera (built-in), single
 * drag strafes the camera through its X/Y plane (= move, not orbit).
 */
class Flutter3DView(context: Context, messenger: BinaryMessenger, id: Int) : PlatformView,
    Flutter3DMethodChannel(messenger, id) {

    private var modelPath by mutableStateOf<String?>(null)

    private val host = ComposePlatformHost(
        context,
        (ArPlugin.activityPluginBinding.activity as LifecycleOwner).lifecycle,
    ).also { host ->
        host.setContent {
            val engine = rememberEngine()
            val modelLoader = rememberModelLoader(engine)
            val materialLoader = rememberMaterialLoader(engine)

            // Strafe-only manipulator: single-finger drag pans the
            // camera instead of orbiting. Pinch still dollies via the
            // unchanged scroll* callbacks.
            val panZoomManipulator = remember {
                object : CameraGestureDetector.DefaultCameraManipulator() {
                    override fun grabBegin(x: Int, y: Int, strafe: Boolean) {
                        super.grabBegin(x, y, /* strafe = */ true)
                    }
                }
            }

            SceneView(
                modifier = Modifier.fillMaxSize(),
                engine = engine,
                modelLoader = modelLoader,
                materialLoader = materialLoader,
                cameraManipulator = panZoomManipulator,
                // autoFitContent moves the camera to fit each model's
                // native size, which leaves the Manipulator's hardcoded
                // speeds (`zoomSpeed=0.05` etc.) too slow for big models
                // and too jumpy for tiny ones. We normalise the model
                // size instead, below.
                autoCenterContent = true,
            ) {
                val path = modelPath
                if (path != null) {
                    val instance = remember(modelLoader, path) {
                        modelLoader.createModelInstance("flutter_assets/$path")
                    }
                    // Free the parent Model (and all of its GPU resources)
                    // when the user swaps to a different glb path so they
                    // don't accumulate across loads.
                    DisposableEffect(instance) {
                        onDispose { modelLoader.destroyModel(instance.model) }
                    }
                    ModelNode(
                        modelInstance = instance,
                        scaleToUnits = FIT_METERS,
                        autoAnimate = true,
                    )
                }
            }
        }
    }

    init { attachMethodChannel() }

    override fun getView(): View = host.view

    override fun dispose() = host.dispose()

    override fun onLoadModel(modelPath: String) {
        this.modelPath = modelPath
    }

    private companion object {
        // Largest-extent target for normalising loaded models. Matches the
        // AR fit so both view types feel sized the same; sits comfortably
        // inside the SceneView default camera's framing (camera at z=2.75
        // looking at origin).
        const val FIT_METERS = 1.5f
    }
}
