import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' show Node, PerspectiveCamera, Scene;
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vector_math/vector_math_64.dart' as vm64;
import 'package:ar/matrix_gesture_detector.dart';

// Camera parameters — match the spirit of the original fixed setup.
// Original: view from (0,0,-1) with fov=60° and aspect=-1. We keep fov=60°
// but use a more natural z=-5 so the model sits comfortably in view.
const double _kCameraZ = 5.0;
const double _kFovY = math.pi / 3; // 60°

// Same conversion helper as transform_ar_view.dart.
vm.Matrix4 _m64ToVm(vm64.Matrix4 m) => vm.Matrix4.fromList(m.storage);

double getScale(Matrix4 m) => math.sqrt(
    m.storage[0] * m.storage[0] +
    m.storage[1] * m.storage[1] +
    m.storage[2] * m.storage[2]);

class _ThreeDScenePainter extends CustomPainter {
  final Scene scene;
  final ValueNotifier<Size?> viewportSize;

  _ThreeDScenePainter({
    required this.scene,
    required this.viewportSize,
    required Listenable repaint,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    viewportSize.value = size;
    scene.render(
      PerspectiveCamera(
        position: vm.Vector3(0, 0, -_kCameraZ),
        target: vm.Vector3.zero(),
        fovRadiansY: _kFovY,
      ),
      canvas,
      viewport: Offset.zero & size,
    );
  }

  @override
  bool shouldRepaint(_ThreeDScenePainter old) => true;
}

class TransformThreeDViewController {
  final ValueNotifier<int> _repaint = ValueNotifier(0);
  final ValueNotifier<Size?> _viewportSize = ValueNotifier(null);

  final Scene scene = Scene();

  Node? _modelNode;
  // Accumulated gesture matrix in Flutter pixel space (vm64, same as framework Matrix4).
  Matrix4 _gestureMatrix = Matrix4.identity();

  TransformThreeDViewController() {
    // Re-apply node transform once the viewport size is known (first paint).
    _viewportSize.addListener(_applyGestureToNode);
  }

  Node? get modelNode => _modelNode;

  set modelNode(Node? node) {
    _modelNode = node;
    if (node != null) {
      scene.add(node);
      _applyGestureToNode();
    }
    _repaint.value++;
  }

  void reset() {
    _gestureMatrix = Matrix4.identity();
    _applyGestureToNode();
    _repaint.value++;
  }

  void dispose() {
    _viewportSize.removeListener(_applyGestureToNode);
    _repaint.dispose();
    _viewportSize.dispose();
  }

  void _applyGestureToNode() {
    final node = _modelNode;
    final size = _viewportSize.value;
    if (node == null || size == null) return;

    final m = _gestureMatrix;
    final tx = m.storage[12]; // pixel translation X
    final ty = m.storage[13]; // pixel translation Y
    final scale = getScale(m);
    // Screen Z rotation maps to world Y rotation (model spin) for a front-facing camera.
    final rotY = math.atan2(m.storage[1], m.storage[0]);

    // Pixels per world unit at z=0 with camera at z=-_kCameraZ, fovY=_kFovY:
    //   visible half-height = _kCameraZ * tan(_kFovY / 2)  [world units]
    //   visible half-height = size.height / 2              [pixels]
    final ppu = size.height / 2 / (_kCameraZ * math.tan(_kFovY / 2));

    final worldTransform = vm64.Matrix4.identity()
      ..translateByDouble(tx / ppu, -ty / ppu, 0.0, 1.0) // flip Y: Flutter Y-down → world Y-up
      ..scaleByDouble(scale, scale, scale, 1.0)
      ..rotateY(rotY + math.pi); // +π: model front faces camera (camera looks in +Z, model designed for -Z)

    node.globalTransform = _m64ToVm(worldTransform);
  }
}

class TransformThreeDView extends StatelessWidget {
  final TransformThreeDViewController controller;

  const TransformThreeDView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return MatrixGestureDetector(
      shouldRotate: false,
      clipChild: false,
      focalPointAlignment: Alignment.topLeft,
      validateMatrix: (m, tDelta, _, __) => _validateMatrix(m, tDelta),
      onMatrixUpdate: (m, _, __, ___) {
        controller._gestureMatrix = m;
        controller._applyGestureToNode();
        controller._repaint.value++;
      },
      child: ColoredBox(
        color: const Color(0xFF000000),
        child: CustomPaint(
          painter: _ThreeDScenePainter(
            scene: controller.scene,
            viewportSize: controller._viewportSize,
            repaint: controller._repaint,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }

  bool _validateMatrix(Matrix4 m, Matrix4 tDelta) {
    final scale = getScale(m);
    if (scale > 20 || scale < 0.5) return false;
    final size = controller._viewportSize.value;
    if (size == null) return true;
    final translation = m.getTranslation();
    translation.scale(1 / scale);
    final translationDelta = tDelta.getTranslation();
    // Allow translation while the object is within viewport bounds,
    // or while the gesture is moving it back toward center.
    return (translation.x.abs() < size.width / 2 ||
            translationDelta.x == 0 ||
            translation.x / translationDelta.x < 0) &&
        (translation.y.abs() < size.height / 2 ||
            translationDelta.y == 0 ||
            translation.y / translationDelta.y < 0);
  }
}
