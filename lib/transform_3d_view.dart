import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Controller for [TransformThreeDView]. Owns the asset path and the
/// per-view method channel created when the platform view is mounted.
class TransformThreeDViewController {
  String? _modelAssetPath;
  MethodChannel? _channel;

  String? get modelAssetPath => _modelAssetPath;

  /// glb asset to render. Set before or after the view is created;
  /// the controller forwards to native as soon as both are ready.
  set modelAssetPath(String? path) {
    _modelAssetPath = path;
    _maybeSendLoadModel();
  }

  void _attach(int id) {
    _channel = MethodChannel('three_d_$id');
    _maybeSendLoadModel();
  }

  void _maybeSendLoadModel() {
    final c = _channel;
    final p = _modelAssetPath;
    if (c != null && p != null) c.invokeMethod('loadModel', {'modelPath': p});
  }

  void dispose() {
    _channel = null;
  }
}

class TransformThreeDView extends StatelessWidget {
  static const String _viewType = 'com.paidviewpoint.three_d';

  final TransformThreeDViewController controller;

  const TransformThreeDView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return defaultTargetPlatform == TargetPlatform.android
        ? AndroidView(
            viewType: _viewType,
            onPlatformViewCreated: controller._attach,
          )
        : UiKitView(
            viewType: _viewType,
            onPlatformViewCreated: controller._attach,
          );
  }
}
