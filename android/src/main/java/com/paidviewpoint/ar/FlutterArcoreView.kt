package com.paidviewpoint.ar

import android.content.Context
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import android.widget.TextView
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.LifecycleOwner
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import com.google.ar.core.Anchor
import com.google.ar.core.Config
import com.google.ar.core.Frame
import com.google.ar.core.Plane
import com.google.ar.core.Pose
import com.google.ar.core.TrackingFailureReason
import com.google.ar.core.TrackingState
import dev.romainguy.kotlin.math.Float3
import dev.romainguy.kotlin.math.Mat4
import dev.romainguy.kotlin.math.cross
import dev.romainguy.kotlin.math.dot
import dev.romainguy.kotlin.math.normalize
import dev.romainguy.kotlin.math.quaternion
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.platform.PlatformView
import io.github.sceneview.SurfaceType
import io.github.sceneview.ar.ARSceneView
import io.github.sceneview.ar.scene.PlaneRenderer
import io.github.sceneview.math.Position
import io.github.sceneview.math.Scale
import io.github.sceneview.model.model
import io.github.sceneview.rememberEngine
import io.github.sceneview.rememberMaterialLoader
import io.github.sceneview.rememberModelLoader
import io.github.sceneview.rememberScene

/**
 * Hosts SceneView's [ARSceneView] inside a [ComposeView]. The glb model
 * is rendered in the same Filament/GL context as the ARCore camera feed
 * and placed when the user taps a vertical plane (wall).
 */
class FlutterArcoreView(context: Context, messenger: BinaryMessenger, id: Int) : PlatformView,
    FlutterArcoreMethodChannel(messenger, id) {

    // Snackbar-pill hint ("Searching for surfaces…", "Tap a wall…",
    // tracking-failure copy) layered on top of the ComposeView in the
    // FrameLayout below.
    private val hintView: TextView = TextView(context).apply {
        val density = context.resources.displayMetrics.density
        val padH = (16 * density).toInt()
        val padV = (10 * density).toInt()
        setPadding(padH, padV, padH, padV)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
        setTextColor(Color.WHITE)
        gravity = Gravity.CENTER
        background = GradientDrawable().apply {
            cornerRadius = 20 * density
            setColor(0xBF323232.toInt())
        }
        visibility = View.GONE
    }
    private var lastHint: String? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    // Reactive Compose state — single source of truth the method channel mutates.
    private var modelPath by mutableStateOf<String?>(null)
    private var fitMeters by mutableStateOf(2.0f)
    private var placedAnchor by mutableStateOf<Anchor?>(null)

    // User adjustments applied to the placed model on top of the auto-fit
    // transform. `modelScale` multiplies the `scaleToUnits` size; X/Y are
    // along the anchor's local axes — after `wallMountedPose` those are
    // horizontal-along-wall and world-up, so dragging keeps the model on
    // the wall surface.
    private var modelScale by mutableStateOf(1.0f)
    private var modelOffsetX by mutableStateOf(0.0f)
    private var modelOffsetY by mutableStateOf(0.0f)

    private val scaleDetector = ScaleGestureDetector(
        context,
        object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
            override fun onScale(detector: ScaleGestureDetector): Boolean {
                modelScale = (modelScale * detector.scaleFactor).coerceIn(MIN_SCALE, MAX_SCALE)
                return true
            }
        },
    )
    private var lastDragX = 0f
    private var lastDragY = 0f
    private var isPanning = false

    // Cache of the last tracking snapshot sent to Dart, used to skip the
    // method-channel hop when nothing changed (onSessionUpdated fires
    // every AR frame).
    private var lastTrackingState: String? = null
    private var lastFailureReason: String? = null
    private var lastHasPlanes: Boolean? = null

    // Latest ARCore Frame, written each tick by onSessionUpdated and read
    // by onTouchEvent. Volatile because the touch callback runs on the UI
    // thread while onSessionUpdated runs on the GL/render thread.
    @Volatile private var latestFrame: Frame? = null

    private val host = ComposePlatformHost(
        context,
        (ArPlugin.activityPluginBinding.activity as LifecycleOwner).lifecycle,
    ).also { host ->
        host.setContent {
            val engine = rememberEngine()
            val modelLoader = rememberModelLoader(engine)
            val materialLoader = rememberMaterialLoader(engine)
            // Share one Scene with both ARSceneView and our PlaneRenderer
            // so the renderer's plane visualizers show up in the same
            // scene ARSceneView renders.
            val scene = rememberScene(engine)
            val customPlaneRenderer = remember(engine, materialLoader, scene) {
                PlaneRenderer(engine, materialLoader, scene).apply {
                    // SceneView's built-in PlaneRenderer is hard-coded to
                    // RENDER_CENTER (horizontals only, via a center hit-test);
                    // RENDER_ALL draws every updated plane regardless of type.
                    // Canonical fix per the View-based ARSceneView pattern in
                    // github.com/SceneView/sceneview-android/issues/54.
                    planeRendererMode = PlaneRenderer.PlaneRendererMode.RENDER_ALL
                }
            }
            DisposableEffect(customPlaneRenderer) {
                onDispose { customPlaneRenderer.destroy() }
            }

            ARSceneView(
                modifier = Modifier.fillMaxSize(),
                scene = scene,
                // TextureSurface (TextureView under the hood) composites
                // inline with the view tree, so the hint TextView layered
                // on top in our FrameLayout actually renders above the AR
                // feed. The default SurfaceType.Surface uses a SurfaceView
                // with z-order-on-top, which would hide overlay UI.
                surfaceType = SurfaceType.TextureSurface,
                engine = engine,
                modelLoader = modelLoader,
                materialLoader = materialLoader,
                // SceneView's built-in renderer is hard-coded to
                // RENDER_CENTER (horizontals only via a center hit-test)
                // and the mode is private to the composable. Disable it
                // and drive our own RENDER_ALL renderer (see
                // github.com/SceneView/sceneview-android/issues/54).
                planeRenderer = false,
                sessionConfiguration = { _, config ->
                    config.planeFindingMode = Config.PlaneFindingMode.VERTICAL
                    config.focusMode = Config.FocusMode.AUTO
                },
                onSessionFailed = { exception ->
                    // Surface ARCore session failures (missing/outdated
                    // ARCore APK, device-not-compatible, camera
                    // permission, etc.) through the shared `ar` channel
                    // so they reach Dart's `lastError` notifier. Without
                    // this they're only visible in logcat.
                    val msg = exception.javaClass.simpleName + ": " +
                        (exception.message ?: "ARCore session failed")
                    mainHandler.post {
                        ArPlugin.channel.invokeMethod("error", msg)
                    }
                },
                onSessionUpdated = { session, frame ->
                    latestFrame = frame
                    val camera = frame.camera
                    // getAllTrackables — not frame.getUpdatedPlanes(),
                    // which only returns the planes that *changed* this
                    // frame; once a wall stabilises hasVertical would
                    // flicker back to false and the hint would oscillate.
                    // Skip the per-frame Collection allocation once placed
                    // — the hint pill is hidden anyway in `computeHint`.
                    val hasVertical = placedAnchor == null && session
                        .getAllTrackables(Plane::class.java)
                        .any { it.type == Plane.Type.VERTICAL && it.trackingState == TrackingState.TRACKING }
                    customPlaneRenderer.update(session, frame)
                    val hint = computeHint(
                        camera.trackingState, camera.trackingFailureReason,
                        hasVertical, placedAnchor != null,
                    )
                    val state = camera.trackingState.name
                    val reason = camera.trackingFailureReason.name
                    val stateChanged = state != lastTrackingState ||
                        reason != lastFailureReason ||
                        hasVertical != lastHasPlanes
                    if (!stateChanged && lastHint == hint) return@ARSceneView
                    lastTrackingState = state
                    lastFailureReason = reason
                    lastHasPlanes = hasVertical
                    mainHandler.post {
                        updateHint(hint)
                        if (stateChanged) onTrackingState(state, reason, hasVertical)
                    }
                },
                onTouchEvent = { event, _ ->
                    // Pre-placement: tap to anchor the model. Post-placement:
                    // pinch to scale, single-finger drag to translate along
                    // the wall plane.
                    scaleDetector.onTouchEvent(event)
                    val anchored = placedAnchor != null
                    if (!anchored) {
                        if (event.actionMasked == MotionEvent.ACTION_UP &&
                            !scaleDetector.isInProgress
                        ) handleTap(event, latestFrame)
                    } else if (event.pointerCount == 1 && !scaleDetector.isInProgress) {
                        handleDrag(event)
                    }
                    if (event.actionMasked == MotionEvent.ACTION_UP ||
                        event.actionMasked == MotionEvent.ACTION_CANCEL
                    ) isPanning = false
                    // Consume post-placement events so SceneView's internal
                    // gesture detector doesn't compete with our pinch/drag.
                    // Pre-placement we let the dispatcher continue (its
                    // default no-op camera manipulator doesn't hurt) so the
                    // ARSceneView's render loop sees the events normally.
                    anchored
                },
            ) {
                val path = modelPath
                val anchor = placedAnchor
                if (path != null && anchor != null) {
                    val instance = remember(modelLoader, path) {
                        modelLoader.createModelInstance("flutter_assets/$path")
                    }
                    DisposableEffect(instance) {
                        onDispose { modelLoader.destroyModel(instance.model) }
                    }
                    AnchorNode(
                        anchor = anchor,
                        // AnchorNode defaults to `isPositionEditable = true`,
                        // which means SceneView's touch dispatcher detaches
                        // the anchor on drag and re-anchors via ARCore —
                        // visually a sudden orientation snap. Disable so our
                        // own pan handler fully controls model placement.
                        apply = { isPositionEditable = false },
                    ) {
                        // Wrap the auto-fit ModelNode in a plain Node that
                        // carries the user's pinch/drag adjustments —
                        // `scaleToUnits` overrides the ModelNode's own scale
                        // parameter, so user scale has to live on a parent
                        // node where it can compose multiplicatively.
                        Node(
                            position = Position(modelOffsetX, modelOffsetY, 0f),
                            scale = Scale(modelScale),
                        ) {
                            ModelNode(
                                modelInstance = instance,
                                scaleToUnits = fitMeters,
                                autoAnimate = true,
                            )
                        }
                    }
                }
            }
        }
    }

    private val rootView: FrameLayout = FrameLayout(context).apply {
        addView(host.view, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        val density = context.resources.displayMetrics.density
        val hintLp = FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            bottomMargin = (24 * density).toInt()
            leftMargin = (24 * density).toInt()
            rightMargin = (24 * density).toInt()
        }
        addView(hintView, hintLp)
    }

    init { attachMethodChannel() }

    override fun getView(): View = rootView

    override fun dispose() = host.dispose()

    /** Called by [FlutterArcoreMethodChannel] when Dart invokes `loadModel`. */
    override fun onLoadModel(modelPath: String, fitMeters: Float) {
        this.modelPath = modelPath
        this.fitMeters = fitMeters
    }

    private fun handleTap(event: MotionEvent, frame: Frame?) {
        val f = frame ?: return
        if (f.camera.trackingState != TrackingState.TRACKING) return
        val hit = f.hitTest(event).firstOrNull { h ->
            val t = h.trackable
            t is Plane && t.type == Plane.Type.VERTICAL &&
                t.isPoseInPolygon(h.hitPose)
        } ?: return
        val plane = hit.trackable as Plane
        val corrected = wallMountedPose(hit.hitPose, f.camera.pose)
        placedAnchor = plane.createAnchor(corrected)
        // Reset user adjustments — the new anchor IS the new origin.
        modelScale = 1.0f
        modelOffsetX = 0.0f
        modelOffsetY = 0.0f
        val hitMatrix = FloatArray(16).also { corrected.toMatrix(it, 0) }
        mainHandler.post { onPlaneTap(hitMatrix) }
    }

    private fun handleDrag(event: MotionEvent) {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                lastDragX = event.x
                lastDragY = event.y
                isPanning = true
            }
            MotionEvent.ACTION_MOVE -> if (isPanning) {
                // Convert pixel deltas to anchor-local meters. fitMeters
                // is the on-wall reference size, so 1 fitMeters per
                // ~viewport-width pixels gives "drag the model across the
                // wall at roughly screen speed".
                val pxPerMeter = host.view.width.toFloat() / fitMeters.coerceAtLeast(0.01f)
                val dx = (event.x - lastDragX) / pxPerMeter
                val dy = (event.y - lastDragY) / pxPerMeter
                modelOffsetX += dx
                modelOffsetY -= dy // screen Y is inverted vs world up
                lastDragX = event.x
                lastDragY = event.y
            }
        }
    }

    /**
     * Build a [Pose] at the tap point whose orientation makes a glTF model
     * "stand up" on the wall:
     *  - +Y aligned to world up
     *  - +Z aligned with the wall normal *toward* the camera (so the model
     *    faces the user regardless of which side of the wall ARCore reports)
     *
     * ARCore vertical-plane poses have Y as the outward normal, so we
     * rebuild the rotation basis explicitly from world up + the chosen
     * forward direction.
     */
    private fun wallMountedPose(hitPose: Pose, cameraPose: Pose): Pose {
        val ny = FloatArray(3).also { hitPose.getTransformedAxis(1, 1f, it, 0) }
        val normal = normalize(Float3(ny[0], ny[1], ny[2]))
        val hitPos = Float3(hitPose.tx(), hitPose.ty(), hitPose.tz())
        val cameraPos = Float3(cameraPose.tx(), cameraPose.ty(), cameraPose.tz())
        val toCamera = normalize(cameraPos - hitPos)
        val forward = if (dot(normal, toCamera) >= 0f) normal else -normal
        val worldUp = Float3(0f, 1f, 0f)
        // Right-handed basis with forward = wall-out toward camera.
        val right = normalize(cross(worldUp, forward))
        val up = cross(forward, right)
        val q = quaternion(Mat4(right, up, forward, hitPos))
        return Pose(
            floatArrayOf(hitPos.x, hitPos.y, hitPos.z),
            floatArrayOf(q.x, q.y, q.z, q.w),
        )
    }

    /**
     * Snackbar copy:
     *  - placed → no hint
     *  - PAUSED + failure → reason-specific copy
     *  - PAUSED, no reason → "searching"
     *  - TRACKING + no planes → "searching"
     *  - TRACKING + planes → "tap a wall"
     */
    private fun computeHint(
        trackingState: TrackingState,
        failureReason: TrackingFailureReason,
        hasPlanes: Boolean,
        hasAnchor: Boolean,
    ): String? {
        if (hasAnchor) return null
        if (trackingState == TrackingState.PAUSED) {
            return when (failureReason) {
                TrackingFailureReason.NONE -> SEARCHING_MESSAGE
                TrackingFailureReason.BAD_STATE -> "Tracking lost. Try moving the camera."
                TrackingFailureReason.INSUFFICIENT_LIGHT -> "Not enough light to track."
                TrackingFailureReason.EXCESSIVE_MOTION -> "Moving too fast — slow down."
                TrackingFailureReason.INSUFFICIENT_FEATURES -> "Point at a more textured surface."
                TrackingFailureReason.CAMERA_UNAVAILABLE -> "Camera is unavailable."
                else -> SEARCHING_MESSAGE
            }
        }
        return if (hasPlanes) TAP_TO_PLACE_MESSAGE else SEARCHING_MESSAGE
    }

    private fun updateHint(message: String?) {
        if (lastHint == message) return
        lastHint = message
        if (message == null) {
            hintView.visibility = View.GONE
        } else {
            hintView.text = message
            hintView.visibility = View.VISIBLE
        }
    }

    companion object {
        private const val SEARCHING_MESSAGE = "Searching for surfaces…"
        private const val TAP_TO_PLACE_MESSAGE = "Tap a wall to place the object."
        private const val MIN_SCALE = 0.25f
        private const val MAX_SCALE = 4.0f
    }
}

