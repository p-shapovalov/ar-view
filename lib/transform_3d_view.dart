import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' show Camera, Node, PerspectiveCamera, Scene;
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vector_math/vector_math_64.dart' as vm64;
import 'package:ar/matrix_gesture_detector.dart';

// flutter_scene's PerspectiveCamera uses a left-handed lookAt
// (right = up × forward) and a +1 in proj[3,2], which mirrors X
// relative to ARCore's right-handed projection*view. _ThreeDCamera
// inherits PerspectiveCamera's configuration (position/target/up/fov)
// but overrides the matrix math to use vector_math's RH OpenGL helpers,
// keeping the 3D and AR views in the same convention.
const double _kCameraZ = 5.0;
const double _kFovY = math.pi / 3; // 60°

// Fraction of the viewport's smaller world-space dimension that the
// model's largest extent should occupy after auto-fit.
const double _kFitMargin = 0.8;

// Same conversion helper as transform_ar_view.dart.
vm.Matrix4 _m64ToVm(vm64.Matrix4 m) => vm.Matrix4.fromList(m.storage);

double getScale(Matrix4 m) => math.sqrt(
    m.storage[0] * m.storage[0] +
    m.storage[1] * m.storage[1] +
    m.storage[2] * m.storage[2]);

/// PerspectiveCamera with a right-handed `projection·view` built from
/// vector_math's OpenGL helpers — same convention as ARCore. Configured
/// with eye = (0, 0, +_kCameraZ) looking toward −Z, +Y up; glTF-standard
/// models (+Y up, facing +Z) then face the camera with no extra rotation.
class _ThreeDCamera extends PerspectiveCamera {
  _ThreeDCamera()
      : super(
          position: vm.Vector3(0, 0, _kCameraZ),
          target: vm.Vector3.zero(),
          up: vm.Vector3(0, 1, 0),
          fovRadiansY: _kFovY,
        );

  @override
  vm.Matrix4 getViewTransform(ui.Size dimensions) {
    final proj = vm.makePerspectiveMatrix(
        fovRadiansY, dimensions.width / dimensions.height, fovNear, fovFar);
    final view = vm.makeViewMatrix(position, target, up);
    return proj * view;
  }
}

class _ThreeDScenePainter extends CustomPainter {
  final Scene scene;
  final Camera camera;
  final ValueNotifier<Size?> viewportSize;

  _ThreeDScenePainter({
    required this.scene,
    required this.camera,
    required this.viewportSize,
    required Listenable repaint,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    viewportSize.value = size;
    scene.render(camera, canvas, viewport: Offset.zero & size);
  }

  @override
  bool shouldRepaint(_ThreeDScenePainter old) => true;
}

class TransformThreeDViewController {
  final ValueNotifier<int> _repaint = ValueNotifier(0);
  final ValueNotifier<Size?> _viewportSize = ValueNotifier(null);

  final Scene scene = Scene();
  final Camera _camera = _ThreeDCamera();

  Node? _modelNode; // user-supplied node (inner, holds auto-fit transform)
  Node? _modelWrapper; // scene-attached wrapper that gestures drive
  // Accumulated gesture matrix in Flutter pixel space (vm64, same as framework Matrix4).
  Matrix4 _gestureMatrix = Matrix4.identity();

  TransformThreeDViewController() {
    // Re-apply node transform once the viewport size is known (first paint).
    _viewportSize.addListener(_onViewportChanged);
  }

  Node? get modelNode => _modelNode;

  set modelNode(Node? node) {
    if (_modelWrapper != null) {
      scene.remove(_modelWrapper!);
      _modelWrapper = null;
    }
    _modelNode = node;
    if (node != null) {
      _modelWrapper = Node(name: 'fit_wrapper')..add(node);
      scene.add(_modelWrapper!);
      _applyAutoFit();
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
    _viewportSize.removeListener(_onViewportChanged);
    _repaint.dispose();
    _viewportSize.dispose();
  }

  void _onViewportChanged() {
    _applyAutoFit();
    _applyGestureToNode();
  }

  /// Auto-fits the model so its largest extent is [_kFitMargin] × the
  /// smaller of the viewport's world-space width/height at z=0.
  /// The fit is baked into the inner node's `localTransform`; gestures
  /// then compose on top via the wrapper's `globalTransform`.
  void _applyAutoFit() {
    final node = _modelNode;
    final size = _viewportSize.value;
    if (node == null || size == null) return;

    final bounds = node.combinedLocalBounds;
    if (bounds == null) return;

    final extent = bounds.max - bounds.min;
    final maxExtent = math.max(extent.x, math.max(extent.y, extent.z));
    if (maxExtent <= 0) return;

    final center = (bounds.min + bounds.max) * 0.5;
    final visH = 2 * _kCameraZ * math.tan(_kFovY / 2);
    final visW = visH * size.width / size.height;
    final target = math.min(visW, visH) * _kFitMargin;
    final s = target / maxExtent;

    node.localTransform = vm.Matrix4.identity()
      ..scaleByDouble(s, s, s, 1.0)
      ..translateByDouble(-center.x, -center.y, -center.z, 1.0);
  }

  void _applyGestureToNode() {
    final wrapper = _modelWrapper;
    final size = _viewportSize.value;
    if (wrapper == null || size == null) return;

    final m = _gestureMatrix;
    final tx = m.storage[12]; // pixel translation X
    final ty = m.storage[13]; // pixel translation Y
    final scale = getScale(m);
    final rotY = math.atan2(m.storage[1], m.storage[0]);

    // Pixels per world unit at z=0: camera is at +_kCameraZ, plane at z=0.
    //   visible half-height = _kCameraZ * tan(_kFovY / 2) [world units]
    //                       = size.height / 2             [pixels]
    final ppu = size.height / 2 / (_kCameraZ * math.tan(_kFovY / 2));

    // Flutter Y-down → world Y-up. X aligns directly with the RH camera's
    // right vector (+X world), so no X flip is needed.
    final worldTransform = vm64.Matrix4.identity()
      ..translateByDouble(tx / ppu, -ty / ppu, 0.0, 1.0)
      ..scaleByDouble(scale, scale, scale, 1.0)
      ..rotateY(rotY);

    wrapper.globalTransform = _m64ToVm(worldTransform);
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
            camera: controller._camera,
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
