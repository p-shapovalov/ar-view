import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:ar/ar.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vector_math/vector_math_64.dart' as vm64;

// AR matrices (from ARFrameResult / Flutter) use vector_math_64.
// flutter_scene (Camera / Node) uses vector_math (non-64).
// These helpers convert at the boundary — Float64List backing is shared.
vm.Matrix4 _m64ToVm(vm64.Matrix4 m) => vm.Matrix4.fromList(m.storage);
vm.Vector3 _v64ToVm(vm64.Vector3 v) => vm.Vector3(v.x, v.y, v.z);

class ArCamera extends Camera {
  vm.Matrix4 _viewProjection = vm.Matrix4.identity();
  vm.Vector3 _position = vm.Vector3.zero();

  void update(vm64.Matrix4 projectionMatrix, vm64.Matrix4 viewMatrix) {
    _viewProjection = _m64ToVm(projectionMatrix) * _m64ToVm(viewMatrix);
    _position = _v64ToVm(vm64.Matrix4.inverted(viewMatrix).getTranslation());
  }

  @override
  vm.Vector3 get position => _position;

  @override
  vm.Matrix4 getViewTransform(ui.Size dimensions) => _viewProjection;
}

class _ArScenePainter extends CustomPainter {
  final Scene scene;
  final ArCamera camera;

  _ArScenePainter({
    required this.scene,
    required this.camera,
    required Listenable repaint,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    scene.render(camera, canvas, viewport: Offset.zero & size);
  }

  @override
  bool shouldRepaint(_ArScenePainter old) => true;
}

class TransformArViewController {
  final ValueNotifier<bool> planeDetected = ValueNotifier(false);
  final ValueNotifier<int> _repaint = ValueNotifier(0);
  final Matrix4 Function(Matrix4 plane, Matrix4 viewProjection)? mapPlane;

  final Scene scene = Scene();
  final ArCamera _arCamera = ArCamera();

  Node? _modelNode;
  Matrix4? planeMatrix;
  Matrix4? planeMatrixOnSurface;

  TransformArViewController({this.mapPlane});

  Node? get modelNode => _modelNode;

  set modelNode(Node? node) {
    _modelNode = node;
    if (node != null) {
      scene.add(node);
      _repaint.value++;
    }
  }

  void reset() {
    planeMatrix = null;
    planeMatrixOnSurface = null;
    _repaint.value++;
  }
}

class TransformArView extends StatelessWidget {
  final TransformArViewController controller;

  const TransformArView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    return Stack(children: [
      ArView(
        width: screenSize.width,
        height: screenSize.height,
        controller: controller,
        onArViewCreated: (_) {},
        onFrame: (f) => _onFrame(context, f),
        onPlaneTap: (p) => _onPlaneTap(context, p),
      ),
      IgnorePointer(
        child: CustomPaint(
          painter: _ArScenePainter(
            scene: controller.scene,
            camera: controller._arCamera,
            repaint: controller._repaint,
          ),
          size: Size.infinite,
        ),
      ),
    ]);
  }

  void _onPlaneTap(BuildContext context, ARHitResult hit) =>
      controller.planeMatrix = hit.hitMatrix;

  void _onFrame(BuildContext context, ARFrameResult frame) {
    controller._arCamera.update(frame.projectionMatrix, frame.viewMatrix);

    var plane = controller.planeMatrix;
    if (plane != null) {
      controller.planeMatrixOnSurface ??=
          _putOnSurface(plane, frame.viewMatrix);

      plane = controller.planeMatrixOnSurface!;
      if (controller.mapPlane != null) {
        plane = controller.mapPlane!(
            plane, frame.projectionMatrix * frame.viewMatrix * plane);
      }
      // Convert vm64 → vm at the flutter_scene boundary
      controller._modelNode?.globalTransform = _m64ToVm(plane);
    }

    controller.planeDetected.value = frame.hasPlanes;
    controller._repaint.value++;
  }

  Matrix4 _putOnSurface(Matrix4 plane, Matrix4 viewMatrix) {
    final p = plane.clone();
    p.rotateX(math.pi / 2);

    final worldUp = vm64.Vector3(0.0, 1.0, 0.0);

    // After rotateX(π/2), p.forward (col2) = original plane normal.
    // Flip around Y if that normal points away from the camera.
    final camPos = Matrix4.inverted(viewMatrix).getTranslation();
    final toCamera = (camPos - p.getTranslation())..normalize();
    if (p.forward.dot(toCamera) < 0) p.rotateY(math.pi);

    final angle = p.up.angleTo(worldUp);
    p.rotateZ(angle);
    if (p.up.angleTo(worldUp) > 0.01) p.rotateZ(-2 * angle);

    return p;
  }
}
