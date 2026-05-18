package com.paidviewpoint.ar

import android.os.Handler
import android.view.MotionEvent
import com.google.android.filament.Engine
import com.google.android.filament.View as FilamentView
import com.google.android.filament.gltfio.FilamentAsset
import io.github.sceneview.node.ModelNode
import io.github.sceneview.node.Node
import io.github.sceneview.utils.pickNode

// gltfio fills this placeholder name for entities without an authored
// glTF name; treat it as "unnamed" when walking for a meaningful label.
private const val GLTFIO_UNNAMED = "<unknown>"

// Hard ceiling on the parent walk so a malformed parent chain can't ANR.
// Well above any plausible glTF nesting depth.
private const val MAX_PARENT_STEPS = 64

/**
 * Reconcile per-node visibility against a set of hidden glTF names.
 * SceneView's `isVisible` doesn't propagate to children, so every node
 * whose ancestry includes a hidden name is set hidden individually.
 */
internal fun applyVisibility(modelNode: ModelNode, hidden: Set<String>) {
    if (hidden.isEmpty()) {
        for (n in modelNode.nodes) n.isVisible = true
        return
    }
    for (n in modelNode.nodes) {
        n.isVisible = !isUnderHidden(n, hidden, modelNode)
    }
}

private fun isUnderHidden(node: Node, hidden: Set<String>, root: ModelNode): Boolean {
    var cur: Node? = node
    while (cur != null && cur !== root) {
        val name = cur.name
        if (name != null && name in hidden) return true
        cur = cur.parent
    }
    return false
}

internal fun listNodeNames(modelNode: ModelNode?): List<String> =
    modelNode?.nodes?.mapNotNull { it.name?.takeIf { n -> n.isNotEmpty() } } ?: emptyList()

/**
 * GPU-pick the renderable under [event] and resolve it to its authored
 * glTF node name via [gltfNodeName]. The callback fires on [handler]
 * once Filament's next frame finishes the pick query (typically 1–2
 * frames). [onResult] receives `null` when nothing was picked or no
 * named ancestor was found.
 */
internal fun pickGltfNodeName(
    view: FilamentView,
    modelNode: ModelNode,
    event: MotionEvent,
    handler: Handler,
    onResult: (String?) -> Unit,
) {
    view.pickNode(event, modelNode.renderableNodes, handler) { picked, _, _ ->
        val entity = picked?.entity ?: 0
        onResult(gltfNodeName(modelNode.modelInstance.asset, modelNode.engine, entity))
    }
}

/**
 * Walk up the asset's transform hierarchy from a renderable entity to
 * the nearest entity with a non-placeholder authored name. gltfio puts
 * the *mesh* name on the renderable entity, not the *node* name — the
 * authored glTF node name sits on the parent entity.
 */
private fun gltfNodeName(asset: FilamentAsset?, engine: Engine, entity: Int): String? {
    if (asset == null || entity == 0) return null
    val tm = engine.transformManager
    val rootEntity = asset.root
    var current = entity
    var stepsLeft = MAX_PARENT_STEPS
    while (current != 0 && current != rootEntity && stepsLeft-- > 0) {
        val name = asset.getName(current)
        if (!name.isNullOrEmpty() && name != GLTFIO_UNNAMED) return name
        val instance = tm.getInstance(current)
        if (instance == 0) break
        // TransformManager.getParent(instance) returns the parent *entity*
        // (0 if `current` is a root), not another instance.
        current = tm.getParent(instance)
    }
    return null
}
