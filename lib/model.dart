import 'package:vector_math/vector_math_64.dart';

Matrix4 _matrixFromJson(dynamic json) =>
    Matrix4.fromList((json as List).cast<double>());

/// ARCore's `TrackingState` enum, mirrored verbatim. PAUSED can mean either
/// "still bootstrapping" (camera just started, no failure) or "tracking lost"
/// — disambiguate via [ARTrackingState.trackingFailureReason]. iOS reports
/// the same enum names (mapped from ARKit's `ARCamera.TrackingState`).
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
/// [ARTrackingState.trackingState] is `paused`. iOS maps its smaller set
/// of `ARCamera.TrackingState.Reason` values onto the same names.
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

class ARHitResult {
  ARHitResult({required this.hitMatrix});

  final Matrix4 hitMatrix;

  static ARHitResult fromJson(dynamic json) =>
      ARHitResult(hitMatrix: _matrixFromJson(json['hitMatrix']));
}

/// Per-frame tracking snapshot streamed from the native renderer.
class ARTrackingState {
  ARTrackingState({
    required this.trackingState,
    required this.trackingFailureReason,
    required this.hasPlanes,
  });

  final ArTrackingState trackingState;
  final ArTrackingFailureReason trackingFailureReason;
  final bool hasPlanes;

  static ARTrackingState fromJson(dynamic json) => ARTrackingState(
        trackingState: _trackingStateFrom(json['trackingState']),
        trackingFailureReason: _failureReasonFrom(json['trackingFailureReason']),
        hasPlanes: json['hasPlanes'] ?? false,
      );
}
