import 'dart:math' as math;

import 'package:ar/ar.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

final _openGlToFlutterRotation =
    vm.Quaternion.axisAngle(vm.Vector3(1.0, 0.0, 0.0), math.pi);

class TransformArViewController {
  final double pixelsPerMeter;
  final Size size;
  final ValueNotifier<Matrix4?> transform;
  final GlobalKey transformKey;
  final Matrix4 Function(Matrix4 plane)? mapPlane;

  Matrix4? planeMatrix;
  Matrix4? planeMatrixOnSurface;
  reset() {
    transform.value = null;
    planeMatrix = null;
    planeMatrixOnSurface = null;
  }

  TransformArViewController(
      {required this.pixelsPerMeter,
      required this.size,
      required this.transform,
      required this.transformKey,
      this.mapPlane});
}

class TransformArView extends StatelessWidget {
  final Widget child;
  final TransformArViewController controller;

  const TransformArView(
      {Key? key, required this.child, required this.controller})
      : super(key: key);

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
      ValueListenableBuilder(
          valueListenable: controller.transform,
          builder: (context, Matrix4? transform, _) => transform == null
              ? Container()
              : Transform(
                  key: controller.transformKey,
                  transform: transform,
                  child: child,
                ))
    ]);
  }

  _onPlaneTap(BuildContext context, ARHitResult hit) =>
      controller.planeMatrix = hit.hitMatrix;

  _onFrame(BuildContext context, ARFrameResult frame) async {
    var plane = controller.planeMatrix;
    if (plane != null) {
      controller.planeMatrixOnSurface ??=
          _putOnSurface(plane, _getFinalTransform(context, plane, frame));

      plane = controller.planeMatrixOnSurface!;
      if (controller.mapPlane != null) plane = controller.mapPlane!(plane);

      controller.transform.value = _getFinalTransform(context, plane, frame);
    }
  }

  Matrix4 _putOnSurface(Matrix4 plane, Matrix4 finalTransform) {
    final p = plane.clone();

    // set as parallel to the surface
    p.rotateX(math.pi / 2);

    final up = vm.Vector3(0.0, 1.0, 0.0);

    vm.Matrix3 finalRotation =
        (finalTransform.clone()..rotateX(math.pi / 2)).getRotation();
    // face to camera - flip if needed
    if (finalRotation.forward.z > 0) p.rotateY(math.pi);
    // turn yAxis to up
    final angle = p.up.angleTo(up);
    p.rotateZ(angle);
    if (p.up.angleTo(up) > 0.01) p.rotateZ(-2 * angle);

    return p;
  }

  Matrix4 _getFinalTransform(
          BuildContext context, Matrix4 plane, ARFrameResult frame) =>
      _mapOpenGlToFlutter(
          context,
          frame.projectionMatrix * frame.viewMatrix * plane,
          controller.pixelsPerMeter);

  Matrix4 _mapOpenGlToFlutter(
      BuildContext context, Matrix4 openGlMatrix, double pixelsPerMeter) {
    final viewSize = MediaQuery.of(context).size;

    // openGlMatrix.invertRotation();
    final flutterToOpenGl = Matrix4.compose(
      // center aligment
      vm.Vector3(-1.0 * controller.size.width / 2 / pixelsPerMeter,
          1.0 * controller.size.height / 2 / pixelsPerMeter, 0.0),
      // rotate original widget to OpenGL-like coordinates
      // so OpenGL->flutter transform will restore original widget
      // with applied model view projection transformation
      _openGlToFlutterRotation,
      // scale according to pixelsPerMeter params
      vm.Vector3(1 / pixelsPerMeter, 1 / pixelsPerMeter, 1.0),
    );
    final openGlToFlutter = Matrix4.compose(
      vm.Vector3(-1.0, 1.0, 0.0),
      _openGlToFlutterRotation,
      vm.Vector3(2 / viewSize.width, 2 / viewSize.height, 1.0),
    )..invert();
    final mvp = openGlToFlutter * openGlMatrix * flutterToOpenGl;
    return mvp;
  }
}
