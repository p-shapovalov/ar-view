import SceneKit

extension SCNNode {
    /// Walks up to the nearest ancestor with a non-empty name, stopping
    /// at `root` (exclusive). Hit-tests land on leaf renderables whose
    /// names are exporter-generated (`Mesh-primitive-0`); the authored
    /// glTF node name sits one level up.
    func firstNamedAncestorName(stoppingAt root: SCNNode) -> String? {
        var cur: SCNNode? = self
        while let n = cur, n !== root {
            if let name = n.name, !name.isEmpty { return name }
            cur = n.parent
        }
        return nil
    }

    /// Names of every named descendant in depth-first order.
    func namedDescendants() -> [String] {
        var names: [String] = []
        enumerateHierarchy { node, _ in
            if let n = node.name, !n.isEmpty { names.append(n) }
        }
        return names
    }

    /// Scales this node so its largest local-AABB extent equals
    /// [targetMeters] and re-pivots so the centroid lands at the origin.
    /// Both `Ios3DView` and `IosARView` rely on this to normalise model
    /// size for consistent gesture feel + framing.
    func autoFit(to targetMeters: Float) {
        let (minV, maxV) = boundingBox
        let extent = SCNVector3(maxV.x - minV.x, maxV.y - minV.y, maxV.z - minV.z)
        let maxExtent = Swift.max(extent.x, Swift.max(extent.y, extent.z))
        guard maxExtent > 0 else { return }
        let s = targetMeters / Float(maxExtent)
        scale = SCNVector3(s, s, s)
        let center = SCNVector3(
            (minV.x + maxV.x) / 2,
            (minV.y + maxV.y) / 2,
            (minV.z + maxV.z) / 2,
        )
        pivot = SCNMatrix4MakeTranslation(center.x, center.y, center.z)
    }
}

/// Holds nodes detached via removeNode so they can be reattached in place
/// by restoreNode. Strong refs keep the subtree alive while off-scene; the
/// parent ref pins the reattachment point.
struct DetachedSubtreeStore {
    private var entries: [String: (node: SCNNode, parent: SCNNode)] = [:]

    /// Detach the first descendant of `root` matching `name`. Returns
    /// true if a node was found and removed.
    mutating func remove(named name: String, from root: SCNNode) -> Bool {
        guard let node = root.childNode(withName: name, recursively: true),
              let parent = node.parent else { return false }
        entries[name] = (node, parent)
        node.removeFromParentNode()
        return true
    }

    mutating func restore(named name: String) -> Bool {
        guard let entry = entries.removeValue(forKey: name) else { return false }
        entry.parent.addChildNode(entry.node)
        return true
    }

    mutating func clear() { entries.removeAll() }
}

extension Comparable {
    /// Swift stdlib has `ClosedRange.clamped(to:)` for ranges but no
    /// `Comparable.clamped(to:)` for values. This is the natural symmetry
    /// of Kotlin's `coerceIn(min, max)`, used to keep both gesture
    /// pipelines visually aligned.
    func clamped(to range: ClosedRange<Self>) -> Self {
        return min(max(self, range.lowerBound), range.upperBound)
    }
}
