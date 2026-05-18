package com.paidviewpoint.ar

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.View
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.LifecycleOwner
import dev.romainguy.kotlin.math.Float3
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.platform.PlatformView
import io.github.sceneview.SceneView
import io.github.sceneview.SurfaceType
import io.github.sceneview.gesture.CameraGestureDetector
import io.github.sceneview.model.model
import io.github.sceneview.node.ModelNode
import io.github.sceneview.rememberEngine
import io.github.sceneview.rememberMaterialLoader
import io.github.sceneview.rememberModelLoader
import io.github.sceneview.rememberOnGestureListener
import io.github.sceneview.rememberScene
import io.github.sceneview.rememberView

/**
 * Non-AR 3D model viewer. Hosts SceneView's `SceneView` composable inside
 * a [ComposePlatformHost]. Pinch dollies the camera (built-in), single
 * drag strafes the camera through its X/Y plane (= move, not orbit).
 */
class Flutter3DView(context: Context, messenger: BinaryMessenger, id: Int) : PlatformView,
    Flutter3DMethodChannel(messenger, id) {

    private var modelPath by mutableStateOf<String?>(null)
    private var modelNodeRef by mutableStateOf<ModelNode?>(null)
    private var hiddenNodeNames by mutableStateOf<Set<String>>(emptySet())

    private val mainHandler = Handler(Looper.getMainLooper())

    private val host = ComposePlatformHost(
        context,
        (ArPlugin.activityPluginBinding.activity as LifecycleOwner).lifecycle,
    ).also { host ->
        host.setContent {
            val engine = rememberEngine()
            val modelLoader = rememberModelLoader(engine)
            val materialLoader = rememberMaterialLoader(engine)
            // Hoisted so the tap handler can drive `view.pickNode` directly
            // — SceneView's onSingleTapConfirmed delivers the picked Node
            // but flattens the glTF parent chain, losing the node names
            // we want to surface.
            val scene = rememberScene(engine)
            val view = rememberView(engine).apply { setScene(scene) }

            // Strafe-only manipulator: single-finger drag pans the
            // camera instead of orbiting. Pinch still dollies via the
            // unchanged scroll* callbacks. Explicit orbit home / target —
            // the no-arg default leaves Filament's eye at (0, 0, 1) which
            // sits *inside* a model sized to FIT_METERS = 1.5, making
            // tap-rays originate from inside the geometry.
            val panZoomManipulator = remember {
                object : CameraGestureDetector.DefaultCameraManipulator(
                    Float3(0f, 0f, 3f),
                    Float3(0f, 0f, 0f),
                ) {
                    override fun grabBegin(x: Int, y: Int, strafe: Boolean) {
                        super.grabBegin(x, y, /* strafe = */ true)
                    }
                }
            }

            val gestureListener = rememberOnGestureListener(
                onSingleTapConfirmed = { e, _ ->
                    val mn = modelNodeRef ?: return@rememberOnGestureListener
                    pickGltfNodeName(view, mn, e, mainHandler) { name ->
                        if (name != null) onNodeTap(name)
                    }
                },
            )

            SceneView(
                modifier = Modifier.fillMaxSize(),
                engine = engine,
                modelLoader = modelLoader,
                materialLoader = materialLoader,
                view = view,
                scene = scene,
                cameraManipulator = panZoomManipulator,
                onGestureListener = gestureListener,
                surfaceType = SurfaceType.TextureSurface,
                // autoCenterContent shifts the rendered model away from
                // its authored origin while leaving collision shapes
                // where they were (SceneView #1430, #1421). Keeping it
                // off makes ray-vs-AABB picking match what's on screen.
                autoCenterContent = false,
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
                        onDispose {
                            modelLoader.destroyModel(instance.model)
                            modelNodeRef = null
                            // Hide-state survives model swaps deliberately —
                            // a same-named node in the new model stays hidden
                            // until restored.
                        }
                    }
                    ModelNode(
                        modelInstance = instance,
                        scaleToUnits = FIT_METERS,
                        autoAnimate = true,
                        apply = { modelNodeRef = this },
                    )
                }
            }

            val mn = modelNodeRef
            val hidden = hiddenNodeNames
            LaunchedEffect(mn, hidden) {
                if (mn != null) applyVisibility(mn, hidden)
            }
        }
    }

    init { attachMethodChannel() }

    override fun getView(): View = host.view

    override fun dispose() = host.dispose()

    override fun onLoadModel(modelPath: String) {
        this.modelPath = modelPath
    }

    override fun onRemoveNode(name: String): Boolean {
        val mn = modelNodeRef ?: return false
        if (mn.nodes.none { it.name == name }) return false
        hiddenNodeNames = hiddenNodeNames + name
        return true
    }

    override fun onRestoreNode(name: String): Boolean {
        if (name !in hiddenNodeNames) return false
        hiddenNodeNames = hiddenNodeNames - name
        return true
    }

    override fun onListNodes(): List<String> = listNodeNames(modelNodeRef)

    private companion object {
        // Largest-extent target for normalising loaded models. Sits
        // comfortably inside the manipulator's orbit-home framing
        // (camera at z=3, target at origin).
        const val FIT_METERS = 1.5f
    }
}
