import 'package:vector_math/vector_math_64.dart';

Matrix4 _matrixFromJson(dynamic json) =>
    Matrix4.fromList((json as List).cast<double>());

/// ARCore's `TrackingState` enum, mirrored verbatim. PAUSED can mean either
/// "still bootstrapping" (camera just started, no failure) or "tracking lost"
/// — disambiguate via [ARFrameResult.trackingFailureReason].
enum ArTrackingState { tracking, paused, stopped, unknown }

ArTrackingState _trackingStateFrom(dynamic name) {
  switch (name) {
    case 'TRACKING':
      return ArTrackingState.tracking;
    case 'PAUSED':
      return ArTrackingState.paused;
    case 'STOPPED':
      return ArTrackingState.stopped;
    default:
      return ArTrackingState.unknown;
  }
}

/// ARCore's `TrackingFailureReason` enum, mirrored verbatim. `none` means
/// "tracking is fine or just bootstrapping" — only treat as a failure when
/// [ARFrameResult.trackingState] is `paused`.
enum ArTrackingFailureReason {
  none,
  badState,
  insufficientLight,
  excessiveMotion,
  insufficientFeatures,
  cameraUnavailable,
  unknown,
}

ArTrackingFailureReason _failureReasonFrom(dynamic name) {
  switch (name) {
    case 'NONE':
      return ArTrackingFailureReason.none;
    case 'BAD_STATE':
      return ArTrackingFailureReason.badState;
    case 'INSUFFICIENT_LIGHT':
      return ArTrackingFailureReason.insufficientLight;
    case 'EXCESSIVE_MOTION':
      return ArTrackingFailureReason.excessiveMotion;
    case 'INSUFFICIENT_FEATURES':
      return ArTrackingFailureReason.insufficientFeatures;
    case 'CAMERA_UNAVAILABLE':
      return ArTrackingFailureReason.cameraUnavailable;
    default:
      return ArTrackingFailureReason.unknown;
  }
}

class ARFrameResult {
  ARFrameResult({
    required this.projectionMatrix,
    required this.viewMatrix,
    required this.hasPlanes,
    required this.trackingState,
    required this.trackingFailureReason,
  });

  final Matrix4 projectionMatrix;
  final Matrix4 viewMatrix;
  final bool hasPlanes;
  final ArTrackingState trackingState;
  final ArTrackingFailureReason trackingFailureReason;

  static ARFrameResult fromJson(dynamic json) => ARFrameResult(
        projectionMatrix: _matrixFromJson(json['projectionMatrix']),
        viewMatrix: _matrixFromJson(json['viewMatrix']),
        hasPlanes: json['hasPlanes'] ?? false,
        trackingState: _trackingStateFrom(json['trackingState']),
        trackingFailureReason: _failureReasonFrom(json['trackingFailureReason']),
      );
}

class ARHitResult {
  ARHitResult({required this.hitMatrix});

  final Matrix4 hitMatrix;

  static ARHitResult fromJson(dynamic json) =>
      ARHitResult(hitMatrix: _matrixFromJson(json['hitMatrix']));
}
