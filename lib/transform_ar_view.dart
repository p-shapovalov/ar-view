import 'package:ar/ar.dart';
import 'package:flutter/material.dart';

// Auto-fit target: the loaded model's largest extent is normalized to fit
// within a 2 m cube, so the placed object reads as roughly 2 m on its
// longest axis regardless of the source asset's authored scale. Sent to
// native via `loadModel` so it applies to the same rendering path that
// actually displays the model.
const double _kArFitMeters = 2.0;

/// Controller for [TransformArView].
///
/// The model is rendered natively on both platforms (SceneView/Filament
/// on Android, SceneKit + GLTFKit2 on iOS) — there is no Dart-side scene
/// graph. The controller's job is to (a) ship the glb asset path across
/// the method channel so the native side can load it, and (b) surface
/// the per-frame tracking state for apps that want a custom UI on top of
/// the default native hint (Android's snackbar pill / iOS's
/// `ARCoachingOverlay`).
class TransformArViewController {
  final ValueNotifier<bool> planeDetected = ValueNotifier(false);
  final ValueNotifier<ArTrackingState> trackingState =
      ValueNotifier(ArTrackingState.unknown);
  final ValueNotifier<ArTrackingFailureReason> trackingFailureReason =
      ValueNotifier(ArTrackingFailureReason.none);

  /// Fires when the user taps a named node on the *placed* model. No
  /// callbacks before placement — those taps are interpreted as
  /// "place the model here" by the native side.
  ArNodeTapCallback? onNodeTap;

  String? _modelAssetPath;
  ArViewController? _arView;

  String? get modelAssetPath => _modelAssetPath;

  /// Asset path the native renderer loads via its glb loader (gltfio on
  /// Android, GLTFKit2 on iOS). Setting after the platform view has been
  /// created sends `loadModel` immediately; setting before the view is
  /// ready buffers the path until [_attachArView] is called.
  set modelAssetPath(String? path) {
    _modelAssetPath = path;
    _maybeSendLoadModel();
  }

  void _attachArView(ArViewController v) {
    _arView = v;
    _maybeSendLoadModel();
  }

  void _maybeSendLoadModel() {
    final v = _arView;
    final p = _modelAssetPath;
    if (v != null && p != null) v.loadModel(p, fitMeters: _kArFitMeters);
  }

  /// Hide the subtree under the named glTF node on the placed model.
  /// Returns false if no model is placed yet or no matching node exists.
  Future<bool> removeNode(String name) async =>
      await _arView?.removeNode(name) ?? false;

  Future<bool> restoreNode(String name) async =>
      await _arView?.restoreNode(name) ?? false;

  Future<List<String>> listNodes() async =>
      await _arView?.listNodes() ?? const [];

  void dispose() {
    planeDetected.dispose();
    trackingState.dispose();
    trackingFailureReason.dispose();
  }
}

class TransformArView extends StatelessWidget {
  final TransformArViewController controller;

  const TransformArView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    return ArView(
      width: screenSize.width,
      height: screenSize.height,
      controller: controller,
      onArViewCreated: controller._attachArView,
      onTrackingState: _onTrackingState,
      onPlaneTap: _onPlaneTap,
      onNodeTap: (name) => controller.onNodeTap?.call(name),
    );
  }

  void _onPlaneTap(ARHitResult hit) {
    // No Dart-side scene to drive — kept as an extension point so apps
    // can react to placement (analytics, UI transitions, etc.).
  }

  void _onTrackingState(ARTrackingState s) {
    controller.planeDetected.value = s.hasPlanes;
    controller.trackingState.value = s.trackingState;
    controller.trackingFailureReason.value = s.trackingFailureReason;
  }
}
