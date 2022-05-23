import 'package:vector_math/vector_math_64.dart';

Matrix4 _matrixFromJson(dynamic json) =>
    Matrix4.fromList((json as List).cast<double>());

class ARFrameResult {
  ARFrameResult({required this.projectionMatrix, required this.viewMatrix});

  final Matrix4 projectionMatrix;
  final Matrix4 viewMatrix;

  static ARFrameResult fromJson(dynamic json) => ARFrameResult(
      projectionMatrix: _matrixFromJson(json['projectionMatrix']),
      viewMatrix: _matrixFromJson(json['viewMatrix']));
}

class ARHitResult {
  ARHitResult({required this.hitMatrix});

  final Matrix4 hitMatrix;

  static ARHitResult fromJson(dynamic json) =>
      ARHitResult(hitMatrix: _matrixFromJson(json['hitMatrix']));
}

// class ARImage {
//   final Uint8List bytes;
//   final int width;
//   final int height;
//   final Matrix4 transformation;
//   ARImage(
//       {required this.bytes,
//       required this.width,
//       required this.height,
//       required this.transformation});

//   Map<String, dynamic> toMap() => <String, dynamic>{
//         'bytes': bytes,
//         'width': width,
//         'height': height,
//         'transformation': transformation.storage
//       };
// }
