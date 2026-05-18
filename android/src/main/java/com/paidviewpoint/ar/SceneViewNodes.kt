package com.paidviewpoint.ar

import io.github.sceneview.node.ModelNode
import io.github.sceneview.node.Node

/**
 * Walks up from the picked SceneView Node to the nearest ancestor with a
 * non-empty name. Hit-tests in SceneView return the leaf renderable, whose
 * name is often exporter-generated (`Mesh-primitive-0`); the authored
 * glTF node name sits one level up.
 */
internal fun firstNamedAncestorName(node: Node, root: ModelNode?): String? {
    var cur: Node? = node
    while (cur != null && cur !== root) {
        val name = cur.name
        if (!name.isNullOrEmpty()) return name
        cur = cur.parent
    }
    return null
}

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
