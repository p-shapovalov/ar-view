import SceneKit

extension SCNNode {
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

extension Comparable {
    /// Swift stdlib has `ClosedRange.clamped(to:)` for ranges but no
    /// `Comparable.clamped(to:)` for values. This is the natural symmetry
    /// of Kotlin's `coerceIn(min, max)`, used to keep both gesture
    /// pipelines visually aligned.
    func clamped(to range: ClosedRange<Self>) -> Self {
        return min(max(self, range.lowerBound), range.upperBound)
    }
}
