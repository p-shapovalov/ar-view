import 'dart:math' as math;

import 'package:flutter_scene/scene.dart' show Node;
import 'package:vector_math/vector_math.dart' as vm;

/// Wraps [model] in a parent node and sets [model]'s `localTransform`
/// so its combined-local AABB is centered at the origin and its largest
/// extent equals [targetSize] (in world units / meters for AR).
///
/// The returned wrapper is what should be added to the scene and is
/// what callers should drive with gesture-derived `globalTransform`
/// writes — the fit is baked into the inner child so gestures compose
/// on top without overwriting it.
///
/// Falls back to an identity inner transform when [model] has no
/// computable bounds (e.g. skinned content).
Node fitNode(Node model, double targetSize) {
  final wrapper = Node(name: 'fit_wrapper');
  final bounds = model.combinedLocalBounds;
  if (bounds != null) {
    final extent = bounds.max - bounds.min;
    final maxExtent = math.max(extent.x, math.max(extent.y, extent.z));
    if (maxExtent > 0) {
      final center = (bounds.min + bounds.max) * 0.5;
      final s = targetSize / maxExtent;
      model.localTransform = vm.Matrix4.identity()
        ..scaleByDouble(s, s, s, 1.0)
        ..translateByDouble(-center.x, -center.y, -center.z, 1.0);
    }
  }
  wrapper.add(model);
  return wrapper;
}
