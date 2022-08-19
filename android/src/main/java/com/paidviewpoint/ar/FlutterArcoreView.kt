package com.paidviewpoint.ar

import android.app.Activity
import android.app.Application
import android.content.Context
import android.opengl.GLES20
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
import common.rendering.BackgroundRenderer
//import common.rendering.ImageRenderer
import common.rendering.PlaneRenderer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.platform.PlatformView
import java.io.IOException
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10

class FlutterArcoreView(context: Context, messenger: BinaryMessenger?, id: Int) : PlatformView,
    FlutterArcoreMethodChannel(messenger, id), GLSurfaceView.Renderer {
    private val backgroundRenderer = BackgroundRenderer()
    private val planeRenderer = PlaneRenderer()
//    private val imageRenderer = ImageRenderer()

    // Rendering. The Renderers are created here, and initialized when the GL surface is created.
    private val surfaceView = GLSurfaceView(context)
    private var installRequested: Boolean
    private var session: Session? = null
    private val displayRotationHelper: DisplayRotationHelper
    private var shouldConfigureSession = false
    private val activityLifecycleCallbacks: Application.ActivityLifecycleCallbacks
    private var activityPaused = false
    private val tapHelper: TapHelper
    private val activity
        get() = ArPlugin.activityPluginBinding.activity

    private var anchor: Anchor? = null

    private fun onPause() {
        if (session != null) {
            // Note that the order matters - GLSurfaceView is paused first so that it does not try
            // to query the session. If Session is paused before GLSurfaceView, GLSurfaceView may
            // still call session.update() and get a SessionPausedException.
            displayRotationHelper.onPause()
            //surfaceView.onPause();
            session!!.pause()
        }
    }

    private fun onResume() {
        if (session == null) {
            var message: String? = null
            try {
                // request to install arcore if not already done
                when (ArCoreApk.getInstance().requestInstall(activity, !installRequested)) {
                    InstallStatus.INSTALL_REQUESTED -> {
                        installRequested = true
                        return
                    }
                    InstallStatus.INSTALLED -> {
                    }
                }

                // create new Session
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
                ArPlugin.channel.invokeMethod("error", message);
                return
            }
            shouldConfigureSession = true
        }
        if (shouldConfigureSession) {
            configureSession()
            shouldConfigureSession = false
        }
        // Note that order matters - see the note in onPause(), the reverse applies here.
        try {
            session!!.resume()
        } catch (e: CameraNotAvailableException) {
            // In some cases (such as another camera app launching) the camera may be given to
            // a different app instead. Handle this properly by showing a message and recreate the
            // session at the next iteration.
            session = null

            ArPlugin.channel.invokeMethod("error", "Camera is not available");
            return
        }
        surfaceView.onResume()
        displayRotationHelper.onResume()

        //fitToScanView.setVisibility(View.VISIBLE); //TODO fix problem later
    }

    private fun configureSession() {
        val config = Config(session)
        config.focusMode = Config.FocusMode.AUTO
        session!!.configure(config)
    }

    override fun onSurfaceCreated(gl: GL10, config: EGLConfig) {
        GLES20.glClearColor(0.1f, 0.1f, 0.1f, 1.0f)

        // Prepare the rendering objects. This involves reading shaders, so may throw an IOException.
        try {
            // Create the texture and pass it to ARCore session to be filled during update().
            backgroundRenderer.createOnGlThread( /*context=*/activity)
            planeRenderer.createOnGlThread(activity, "models/trigrid.png")
//            imageRenderer.createOnGlThread(activity, "models/trigrid.png")
        } catch (e: IOException) {
            Log.e(TAG, "Failed to read an asset file", e)
        }
    }

    override fun onSurfaceChanged(gl: GL10, width: Int, height: Int) {
        displayRotationHelper.onSurfaceChanged(width, height)
        GLES20.glViewport(0, 0, width, height)
    }

    override fun onDrawFrame(gl: GL10) {
        // Clear screen to notify driver it should not load any pixels from previous frame.
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT)
        if (session == null) return

        // Notify ARCore session that the view size changed so that the perspective matrix and
        // the video background can be properly adjusted.
        displayRotationHelper.updateSessionIfNeeded(session)
        if (activityPaused) return

        try {
            session!!.setCameraTextureName(backgroundRenderer.textureId)

            // Obtain the current frame from ARSession. When the configuration is set to
            // UpdateMode.BLOCKING (it is by default), this will throttle the rendering to the
            // camera frame rate.
            val frame = session!!.update()

            // Draw background.
            backgroundRenderer.draw(frame)

            val camera = frame.camera


            val projectionMatrix = FloatArray(16)
            camera.getProjectionMatrix(projectionMatrix, 0, 0.1f, 100.0f)
            val viewMatrix = FloatArray(16)
            camera.getViewMatrix(viewMatrix, 0)

            // If not tracking, don't draw 3d objects.
            if (camera.trackingState != TrackingState.TRACKING) return
            val planes = session!!.getAllTrackables(Plane::class.java)
                    .filter { it.type == Plane.Type.VERTICAL }

            activity.runOnUiThread { onFrame(projectionMatrix, viewMatrix, planes.isNotEmpty()) }

            if (anchor != null) return
            handleTap(frame, camera)
            planeRenderer.drawPlanes(planes,
                camera.displayOrientedPose,
                projectionMatrix
            )


//            imageRenderer.draw(activity, viewMatrix, projectionMatrix)
        } catch (t: Throwable) {
            // Avoid crashing the application due to unhandled exceptions.
            Log.e(TAG, "Exception on the OpenGL thread", t)
        }
    }

    // Handle only one tap per frame, as taps are usually low frequency compared to frame rate.
    private fun handleTap(frame: Frame, camera: Camera) {
        if (camera.trackingState != TrackingState.TRACKING) return
        val tap = tapHelper.poll() ?: return
        val res =  frame.hitTest(tap)
        val hitResults = res.filter { hit ->
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
//            onPause()
        }
    }

    override fun getView(): View {
        return surfaceView
    }

    override fun dispose() {}

//    override fun addImage(image: FlutterArCoreImage) {
//        activity.runOnUiThread {
//        imageRenderer.updateImage(image.bytes)
//        imageRenderer.updateModelMatrix(image.transformation, 1f)
//        }
//    }

    companion object {
        private val TAG = FlutterArcoreView::class.java.simpleName
    }

    init {
        init()
        displayRotationHelper = DisplayRotationHelper( /*context=*/context)


        // Set up renderer.
        surfaceView.preserveEGLContextOnPause = true
        surfaceView.setEGLContextClientVersion(2)
        surfaceView.setEGLConfigChooser(8, 8, 8, 8, 16, 0) // Alpha used for plane blending.
        surfaceView.setRenderer(this)
        surfaceView.renderMode = GLSurfaceView.RENDERMODE_CONTINUOUSLY
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

            override fun onActivityStopped(activity: Activity) {
                onPause()
            }

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
            ArPlugin.channel.invokeMethod("error", "Undefined error");
        }
    }
}