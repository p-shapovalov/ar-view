package com.paidviewpoint.ar

import android.app.Activity
import android.app.Application
import android.content.Context
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.opengl.GLSurfaceView
import android.os.Bundle
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import android.widget.TextView
import com.google.ar.core.*
import com.google.ar.core.ArCoreApk.InstallStatus
import com.google.ar.core.exceptions.CameraNotAvailableException
import com.google.ar.core.exceptions.UnavailableDeviceNotCompatibleException
import com.google.ar.core.exceptions.UnavailableUserDeclinedInstallationException
import common.helpers.DisplayRotationHelper
import common.helpers.TapHelper
import common.helpers.TrackingStateHelper
import common.samplerender.SampleRender
import common.samplerender.arcore.BackgroundRenderer
import common.samplerender.arcore.PlaneRenderer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.platform.PlatformView
import java.io.IOException

class FlutterArcoreView(context: Context, messenger: BinaryMessenger, id: Int) : PlatformView,
    FlutterArcoreMethodChannel(messenger, id), SampleRender.Renderer {

    // Held so `dispose()` can unregister our application-level lifecycle callbacks.
    private val application = context.applicationContext as Application

    // GLES3 rendering framework + AR helpers.
    private val surfaceView = GLSurfaceView(context)
    private val render: SampleRender = SampleRender(surfaceView, this, context.assets)
    private var backgroundRenderer: BackgroundRenderer? = null
    private var planeRenderer: PlaneRenderer? = null
    private var hasSetCameraTextureName = false

    // Native instruction overlay (snackbar-style pill at the bottom). The state machine
    // mirrors hello_ar_java's HelloArActivity#onDrawFrame: searching → tap-to-place →
    // hidden, with TrackingFailureReason strings surfaced when tracking is paused.
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
    private val rootView: FrameLayout = FrameLayout(context).apply {
        addView(surfaceView, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        val density = context.resources.displayMetrics.density
        val hintLp = FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            bottomMargin = (24 * density).toInt()
            leftMargin = (24 * density).toInt()
            rightMargin = (24 * density).toInt()
        }
        addView(hintView, hintLp)
    }
    private var lastHint: String? = null

    private var installRequested: Boolean
    // @Volatile so the GL thread sees `session = null` (set on dispose) without caching.
    @Volatile private var session: Session? = null
    @Volatile private var disposed = false
    private val displayRotationHelper: DisplayRotationHelper
    private var shouldConfigureSession = false
    private val activityLifecycleCallbacks: Application.ActivityLifecycleCallbacks
    private var activityPaused = false
    private val tapHelper: TapHelper
    private val trackingStateHelper: TrackingStateHelper
    private val activity get() = ArPlugin.activityPluginBinding.activity

    private var anchor: Anchor? = null

    private fun onPause() {
        if (disposed) return
        if (session != null) {
            // Note that the order matters - GLSurfaceView is paused first so that it does not try
            // to query the session. If Session is paused before GLSurfaceView, GLSurfaceView may
            // still call session.update() and get a SessionPausedException.
            displayRotationHelper.onPause()
            session!!.pause()
        }
    }

    private fun onResume() {
        if (disposed) return
        if (session == null) {
            var message: String? = null
            try {
                when (ArCoreApk.getInstance().requestInstall(activity, !installRequested)) {
                    InstallStatus.INSTALL_REQUESTED -> {
                        installRequested = true
                        return
                    }
                    InstallStatus.INSTALLED -> {}
                }

                session = Session(activity)
                Log.i(TAG, "Session created ")
            } catch (e: UnavailableUserDeclinedInstallationException) {
                message = "Please install ARCore"
            } catch (e: UnavailableDeviceNotCompatibleException) {
                message = "This device does not support AR"
            } catch (e: Exception) {
                message = "Failed to create AR session"
            }
            if (message != null) {
                ArPlugin.channel.invokeMethod("error", message)
                return
            }
            shouldConfigureSession = true
        }
        if (shouldConfigureSession) {
            configureSession()
            shouldConfigureSession = false
        }
        try {
            session!!.resume()
        } catch (e: CameraNotAvailableException) {
            // In some cases (such as another camera app launching) the camera may be given to
            // a different app instead. Close the just-created session so its native resources
            // don't leak, then null it out so the next onResume() attempts a fresh create.
            session?.close()
            session = null
            ArPlugin.channel.invokeMethod("error", "Camera is not available")
            return
        }
        surfaceView.onResume()
        displayRotationHelper.onResume()
        // Force a re-bind of the camera texture on the next frame, in case the session was
        // recreated above.
        hasSetCameraTextureName = false
    }

    private fun configureSession() {
        val config = Config(session)
        config.focusMode = Config.FocusMode.AUTO
        session!!.configure(config)
    }

    override fun onSurfaceCreated(render: SampleRender) {
        try {
            backgroundRenderer = BackgroundRenderer(render).also {
                // Use the plain camera-feed shader; depth visualization and occlusion are
                // unused (we don't call drawVirtualScene), so we skip loading those shaders.
                it.setUseDepthVisualization(render, false)
            }
            planeRenderer = PlaneRenderer(render)
        } catch (e: IOException) {
            Log.e(TAG, "Failed to read a required asset file", e)
            ArPlugin.channel.invokeMethod("error", "Failed to load AR shaders")
        }
    }

    override fun onSurfaceChanged(render: SampleRender, width: Int, height: Int) {
        displayRotationHelper.onSurfaceChanged(width, height)
    }

    override fun onDrawFrame(render: SampleRender) {
        val session = this.session ?: return
        val bg = backgroundRenderer ?: return
        val planes = planeRenderer ?: return

        // Notify ARCore session that the view size changed so that the perspective matrix and
        // the video background can be properly adjusted.
        displayRotationHelper.updateSessionIfNeeded(session)
        if (activityPaused) return

        // Bind the camera texture once per session — subsequent calls are no-ops, but the texture
        // id changes whenever the session is recreated (e.g. after pause/resume).
        if (!hasSetCameraTextureName) {
            session.setCameraTextureName(bg.cameraColorTexture.textureId)
            hasSetCameraTextureName = true
        }

        try {
            // Obtain the current frame from ARSession. When the configuration is set to
            // UpdateMode.BLOCKING (it is by default), this will throttle the rendering to the
            // camera frame rate.
            val frame = session.update()
            val camera = frame.camera

            bg.updateDisplayGeometry(frame)
            bg.drawBackground(render)

            // Hold the screen on while tracking; let it sleep when tracking stops.
            trackingStateHelper.updateKeepScreenOnFlag(camera.trackingState)

            val projectionMatrix = FloatArray(16)
            camera.getProjectionMatrix(projectionMatrix, 0, 0.1f, 100.0f)
            val viewMatrix = FloatArray(16)
            camera.getViewMatrix(viewMatrix, 0)

            // Even when not tracking, surface state to Dart so apps can build custom UIs.
            // We compute plane info only when tracking is healthy.
            val isTracking = camera.trackingState == TrackingState.TRACKING
            val verticalPlanes = if (isTracking) {
                session.getAllTrackables(Plane::class.java)
                    .filter { it.type == Plane.Type.VERTICAL && it.trackingState == TrackingState.TRACKING }
            } else {
                emptyList()
            }
            val trackingStateName = camera.trackingState.name
            val failureReasonName = camera.trackingFailureReason.name
            val hintMessage = computeHint(camera, verticalPlanes.isNotEmpty(), anchor != null)
            activity.runOnUiThread {
                updateHint(hintMessage)
                onFrame(
                    projectionMatrix,
                    viewMatrix,
                    verticalPlanes.isNotEmpty(),
                    trackingStateName,
                    failureReasonName,
                )
            }

            if (!isTracking) return
            if (anchor != null) return
            handleTap(frame, camera)
            planes.drawPlanes(render, verticalPlanes, camera.displayOrientedPose, projectionMatrix)
        } catch (t: Throwable) {
            Log.e(TAG, "Exception on the OpenGL thread", t)
        }
    }

    private fun handleTap(frame: Frame, camera: Camera) {
        if (camera.trackingState != TrackingState.TRACKING) return
        val tap = tapHelper.poll() ?: return
        val hitResults = frame.hitTest(tap).filter { hit ->
            hit.trackable?.let {
                it is Plane &&
                        it.type == Plane.Type.VERTICAL &&
                        it.isPoseInPolygon(hit.hitPose) &&
                        PlaneRenderer.calculateDistanceToPlane(hit.hitPose, camera.pose) > 0
            } ?: false
        }

        if (hitResults.isNotEmpty()) {
            val hitResult = hitResults.first()
            val centerPose = (hitResult.trackable as Plane).centerPose
            anchor = hitResult.trackable.createAnchor(centerPose)
            activity.runOnUiThread { onPlaneTap(hitResult.hitPose) }
        }
    }

    /**
     * State machine mirroring `HelloArActivity#onDrawFrame`:
     *  - placed model → no hint
     *  - PAUSED + failure reason → reason-specific copy
     *  - PAUSED, no reason → "searching" (still bootstrapping)
     *  - TRACKING + no planes → "searching"
     *  - TRACKING + planes → "tap a wall"
     *
     * Returns the hint text to show, or `null` to hide the overlay.
     */
    private fun computeHint(camera: Camera, hasPlanes: Boolean, hasAnchor: Boolean): String? {
        if (hasAnchor) return null
        if (camera.trackingState == TrackingState.PAUSED) {
            return if (camera.trackingFailureReason == TrackingFailureReason.NONE) {
                SEARCHING_MESSAGE
            } else {
                TrackingStateHelper.getTrackingFailureReasonString(camera)
            }
        }
        return if (hasPlanes) TAP_TO_PLACE_MESSAGE else SEARCHING_MESSAGE
    }

    /** Updates the snackbar pill, skipping no-op writes so the view tree doesn't churn. */
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

    override fun getView(): View = rootView

    /**
     * Releases the AR session (and its hold on the camera), the GL surface, the touch listener
     * and the application-level lifecycle callbacks. Must run when the Flutter side removes this
     * platform view, otherwise a re-open of the AR route reports `CAMERA_UNAVAILABLE` because
     * ARCore can only own the camera through a single live `Session`.
     */
    override fun dispose() {
        if (disposed) return
        disposed = true

        surfaceView.setOnTouchListener(null)
        application.unregisterActivityLifecycleCallbacks(activityLifecycleCallbacks)

        // Hand off the session reference, then null the field so the GL thread's
        // `val session = this.session ?: return` early-returns on any further frames.
        val sessionToClose = session
        session = null
        anchor = null

        // Close on the GL thread so it can't race with an in-flight `session.update()`.
        // queueEvent runs before the thread fully pauses.
        if (sessionToClose != null) {
            surfaceView.queueEvent { sessionToClose.close() }
        }
        surfaceView.onPause()
        displayRotationHelper.onPause()
    }

    companion object {
        private val TAG = FlutterArcoreView::class.java.simpleName

        // Domain-specific copy (we only place on vertical planes — "walls"). To localize,
        // override these strings via app resources and reference R.string here.
        private const val SEARCHING_MESSAGE = "Searching for surfaces…"
        private const val TAP_TO_PLACE_MESSAGE = "Tap a wall to place the object."
    }

    init {
        init()
        displayRotationHelper = DisplayRotationHelper(/*context=*/ context)

        activityLifecycleCallbacks = object : Application.ActivityLifecycleCallbacks {
            override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}
            override fun onActivityStarted(activity: Activity) {}
            override fun onActivityResumed(activity: Activity) {
                activityPaused = false
                onResume()
            }

            override fun onActivityPaused(activity: Activity) {
                activityPaused = true
                onPause()
            }

            override fun onActivityStopped(activity: Activity) { onPause() }
            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
            override fun onActivityDestroyed(activity: Activity) {
                application.unregisterActivityLifecycleCallbacks(this)
            }
        }
        application.registerActivityLifecycleCallbacks(activityLifecycleCallbacks)
        installRequested = false

        tapHelper = TapHelper(activity).also { surfaceView.setOnTouchListener(it) }
        trackingStateHelper = TrackingStateHelper(activity)
        try {
            onResume()
        } catch (e: Exception) {
            ArPlugin.channel.invokeMethod("error", "Undefined error")
        }
    }
}
