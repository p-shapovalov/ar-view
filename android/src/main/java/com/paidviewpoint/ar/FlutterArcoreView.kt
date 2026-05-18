package com.paidviewpoint.ar

import android.app.Activity
import android.app.Application
import android.content.Context
import android.opengl.GLSurfaceView
import android.os.Bundle
import android.util.Log
import android.view.View
import com.google.ar.core.*
import com.google.ar.core.ArCoreApk.InstallStatus
import com.google.ar.core.exceptions.CameraNotAvailableException
import com.google.ar.core.exceptions.UnavailableDeviceNotCompatibleException
import com.google.ar.core.exceptions.UnavailableUserDeclinedInstallationException
import common.helpers.DisplayRotationHelper
import common.helpers.TapHelper
import common.samplerender.SampleRender
import common.samplerender.arcore.BackgroundRenderer
import common.samplerender.arcore.PlaneRenderer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.platform.PlatformView
import java.io.IOException

class FlutterArcoreView(context: Context, messenger: BinaryMessenger, id: Int) : PlatformView,
    FlutterArcoreMethodChannel(messenger, id), SampleRender.Renderer {

    // GLES3 rendering framework + AR helpers.
    private val surfaceView = GLSurfaceView(context)
    private val render: SampleRender = SampleRender(surfaceView, this, context.assets)
    private var backgroundRenderer: BackgroundRenderer? = null
    private var planeRenderer: PlaneRenderer? = null
    private var hasSetCameraTextureName = false

    private var installRequested: Boolean
    private var session: Session? = null
    private val displayRotationHelper: DisplayRotationHelper
    private var shouldConfigureSession = false
    private val activityLifecycleCallbacks: Application.ActivityLifecycleCallbacks
    private var activityPaused = false
    private val tapHelper: TapHelper
    private val activity get() = ArPlugin.activityPluginBinding.activity

    private var anchor: Anchor? = null

    private fun onPause() {
        if (session != null) {
            // Note that the order matters - GLSurfaceView is paused first so that it does not try
            // to query the session. If Session is paused before GLSurfaceView, GLSurfaceView may
            // still call session.update() and get a SessionPausedException.
            displayRotationHelper.onPause()
            session!!.pause()
        }
    }

    private fun onResume() {
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
            // a different app instead. Handle this properly by showing a message and recreate the
            // session at the next iteration.
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

            val projectionMatrix = FloatArray(16)
            camera.getProjectionMatrix(projectionMatrix, 0, 0.1f, 100.0f)
            val viewMatrix = FloatArray(16)
            camera.getViewMatrix(viewMatrix, 0)

            // If not tracking, don't draw 3d objects.
            if (camera.trackingState != TrackingState.TRACKING) return

            val verticalPlanes = session.getAllTrackables(Plane::class.java)
                .filter { it.type == Plane.Type.VERTICAL }

            activity.runOnUiThread { onFrame(projectionMatrix, viewMatrix, verticalPlanes.isNotEmpty()) }

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

    override fun getView(): View = surfaceView

    override fun dispose() {}

    companion object {
        private val TAG = FlutterArcoreView::class.java.simpleName
    }

    init {
        init()
        displayRotationHelper = DisplayRotationHelper(/*context=*/ context)

        val application = context.applicationContext as Application
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
        try {
            onResume()
        } catch (e: Exception) {
            ArPlugin.channel.invokeMethod("error", "Undefined error")
        }
    }
}
