package com.paidviewpoint.ar

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Recomposer
import androidx.compose.ui.platform.AndroidUiDispatcher
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.ViewCompositionStrategy
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.savedstate.SavedStateRegistry
import androidx.savedstate.SavedStateRegistryController
import androidx.savedstate.SavedStateRegistryOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.plus

/**
 * A [LifecycleOwner] + [SavedStateRegistryOwner] that mirrors a parent
 * [Lifecycle] (typically the host activity's) into a per-PlatformView
 * registry, so:
 *  - SceneView's internal `DefaultLifecycleObserver` receives the real
 *    `ON_PAUSE` / `ON_RESUME` from the host activity — heavy native
 *    resources (ARCore session, Filament engine) get paused on background.
 *  - The composition can be torn down independently of the activity by
 *    calling [destroy] from `PlatformView.dispose()`, so multiple platform
 *    views opened over the activity's lifetime don't leak.
 *
 * Flutter's `PlatformView` contract doesn't expose `onPause`/`onResume`
 * (see flutter/flutter#34156), so forwarding from the host lifecycle is
 * the canonical hook.
 */
class ForwardingLifecycleOwner(private val parent: Lifecycle) :
    LifecycleOwner, SavedStateRegistryOwner {

    private val registry = LifecycleRegistry(this)
    private val savedStateController = SavedStateRegistryController.create(this).also {
        it.performRestore(null)
    }
    private val parentObserver = LifecycleEventObserver { _, event ->
        // handleLifecycleEvent walks state correctly even if we're past
        // the event being dispatched.
        if (registry.currentState != Lifecycle.State.DESTROYED) {
            registry.handleLifecycleEvent(event)
        }
    }

    init {
        // Adopt the parent's current state first (so observers don't see a
        // spurious INITIALIZED → CREATED transition after the activity is
        // already RESUMED), then subscribe to subsequent transitions.
        registry.currentState = parent.currentState
        parent.addObserver(parentObserver)
    }

    override val lifecycle: Lifecycle get() = registry
    override val savedStateRegistry: SavedStateRegistry
        get() = savedStateController.savedStateRegistry

    fun destroy() {
        if (registry.currentState == Lifecycle.State.DESTROYED) return
        // Detach from the parent FIRST so the activity's LifecycleRegistry
        // doesn't retain us — opening a route N times would otherwise
        // accumulate N stale observers on the host activity.
        parent.removeObserver(parentObserver)
        // setCurrentState walks down through CREATED → DESTROYED dispatching
        // every event, so observers (SceneView, the Compose recomposer) get
        // clean teardown regardless of where the parent currently is.
        registry.currentState = Lifecycle.State.DESTROYED
    }
}

/**
 * A [ComposeView] host wired with everything Compose needs that Flutter's
 * `FlutterView` doesn't provide:
 *
 *  - A [ForwardingLifecycleOwner] forwarding from [hostLifecycle], set as
 *    the view-tree LifecycleOwner.
 *  - A [SavedStateRegistry] (FlutterActivity isn't a `SavedStateRegistryOwner`).
 *  - A self-managed [Recomposer] passed via `setParentCompositionContext`,
 *    so Compose's default factory's tree walk for a window-level
 *    `ViewTreeLifecycleOwner` (which crashes on FlutterView) never runs.
 *
 * Returns a configured [ComposeView] via [view]; the caller wires
 * `setContent { ... }` and either returns the view directly from
 * `PlatformView.getView()` or wraps it in their own container. Call
 * [dispose] from `PlatformView.dispose()`.
 */
class ComposePlatformHost(context: Context, hostLifecycle: Lifecycle) {
    val lifecycleOwner = ForwardingLifecycleOwner(hostLifecycle)
    private val recomposeContext = AndroidUiDispatcher.CurrentThread + Job()
    private val recomposeScope = CoroutineScope(recomposeContext)
    private val recomposer = Recomposer(recomposeContext).also { rec ->
        recomposeScope.launch { rec.runRecomposeAndApplyChanges() }
    }

    val view: ComposeView = ComposeView(context).apply {
        setViewTreeLifecycleOwner(lifecycleOwner)
        setViewTreeSavedStateRegistryOwner(lifecycleOwner)
        setParentCompositionContext(recomposer)
        setViewCompositionStrategy(
            ViewCompositionStrategy.DisposeOnLifecycleDestroyed(lifecycleOwner.lifecycle)
        )
    }

    fun setContent(content: @Composable () -> Unit) = view.setContent(content)

    fun dispose() {
        lifecycleOwner.destroy()
        recomposer.close()
        recomposeScope.cancel()
        (view.parent as? android.view.ViewGroup)?.removeView(view)
    }
}
