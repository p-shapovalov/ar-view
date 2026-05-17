import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import 'package:ar/matrix_gesture_detector.dart';

final _projection = vm.makePerspectiveMatrix(vm.radians(60), -1, 1, 1000);
final _view = vm.makeViewMatrix(
    vm.Vector3(0.0, 0.00, -1), vm.Vector3(0.0, 0, 0), vm.Vector3(0, 1, 0));

double getScale(Matrix4 m) => math.sqrt([
      m.storage[0],
      m.storage[1],
      m.storage[2]
    ].map((d) => d * d).reduce((v, e) => v + e));

class TransformThreeDView extends StatelessWidget {
  final Widget child;
  final ValueNotifier<Matrix4?> transform;
  final GlobalKey transformKey;
  // final Widget Function(Widget child) transformBuilder;

  final Size size;
  Offset get center => Offset(size.width / 2, size.height / 2);

  TransformThreeDView(
      {super.key,
      required this.child,
      required this.transformKey,
      required this.transform,
      required this.size}) {
    if (transform.value == null) setProjection(Matrix4.identity());
  }

  Matrix4 setProjection(Matrix4 t) => transform.value = Matrix4.identity()
    // The origin center alignment
    ..translateByDouble(center.dx, center.dy, 0, 1)
    ..multiply(_projection * _view * t)
    ..translateByDouble(-center.dx, -center.dy, 0, 1);

  bool validateMatrix(Matrix4 t, Matrix4 tDelta, Matrix4 tScale) {
    final scale = getScale(t);
    if (scale > 20 || scale < 0.5) return false;
    final translation = t.getTranslation(),
        translationDelta = tDelta.getTranslation();
    translation.scale(1 / scale);
    return (translation.x.abs() < center.dx ||
            translation.x / translationDelta.x < 0) &&
        (translation.y.abs() < center.dy ||
            translation.y / translationDelta.y < 0);
  }

  @override
  Widget build(BuildContext context) => Stack(children: [
        Positioned.fill(
            child: Align(
                child: ValueListenableBuilder(
                    valueListenable: transform,
                    builder: (context, Matrix4? transform, _) =>
                        transform == null
                            ? Container()
                            : Transform(
                                key: transformKey,
                                transform: transform,
                                child: MatrixGestureDetector(
                                  shouldRotate: false,
                                  clipChild: false,
                                  focalPointAlignment: Alignment.topLeft,
                                  validateMatrix:
                                      (m, translationDelta, scaleDelta, _) =>
                                          validateMatrix(m.clone(),
                                              translationDelta, scaleDelta),
                                  onMatrixUpdate: (m, _, __, ___) =>
                                      setProjection(m),
                                  child: child,
                                )))))
      ]);
}
