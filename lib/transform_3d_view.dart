import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef NodeTapCallback = void Function(String name);

/// Controller for [TransformThreeDView]. Owns the asset path and the
/// per-view method channel created when the platform view is mounted.
class TransformThreeDViewController {
  String? _modelAssetPath;
  MethodChannel? _channel;

  /// Fires when the user taps a named node in the rendered model. The
  /// `name` is the glTF node name of the nearest named ancestor of the
  /// hit point — exporters usually preserve the authoring tool's name,
  /// so this is what designers will reference.
  NodeTapCallback? onNodeTap;

  String? get modelAssetPath => _modelAssetPath;

  /// glb asset to render. Set before or after the view is created;
  /// the controller forwards to native as soon as both are ready.
  set modelAssetPath(String? path) {
    _modelAssetPath = path;
    _maybeSendLoadModel();
  }

  void _attach(int id) {
    final c = MethodChannel('three_d_$id');
    c.setMethodCallHandler(_handleMethodCall);
    _channel = c;
    _maybeSendLoadModel();
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onNodeTap':
        final name = (call.arguments as Map?)?['name'] as String?;
        if (name != null) onNodeTap?.call(name);
        break;
    }
  }

  void _maybeSendLoadModel() {
    final c = _channel;
    final p = _modelAssetPath;
    if (c != null && p != null) c.invokeMethod('loadModel', {'modelPath': p});
  }

  /// Detaches the subtree rooted at the named glTF node from the rendered
  /// scene. Returns true if a matching node was found and removed. The
  /// node is retained natively so [restoreNode] can reattach it in place.
  Future<bool> removeNode(String name) async {
    final c = _channel;
    if (c == null) return false;
    final r = await c.invokeMethod<bool>('removeNode', {'name': name});
    return r ?? false;
  }

  /// Reattaches a node previously hidden by [removeNode]. Returns true
  /// if a node was waiting under this name.
  Future<bool> restoreNode(String name) async {
    final c = _channel;
    if (c == null) return false;
    final r = await c.invokeMethod<bool>('restoreNode', {'name': name});
    return r ?? false;
  }

  /// Names of every named node in the currently loaded model, in
  /// depth-first order. Useful for debugging — production callers
  /// typically already know the names they want to address.
  Future<List<String>> listNodes() async {
    final c = _channel;
    if (c == null) return const [];
    final r = await c.invokeMethod<List<dynamic>>('listNodes');
    return r?.cast<String>() ?? const [];
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
