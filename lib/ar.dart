import 'dart:async';

import 'package:ar/model.dart';
import 'package:ar/transform_ar_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';

export 'package:ar/model.dart';
export 'package:ar/transform_ar_view.dart';
export 'package:ar/transform_3d_view.dart';

ValueNotifier<String?> lastError = ValueNotifier(null);

MethodChannel _commonChannel = const MethodChannel('ar')
  ..setMethodCallHandler(_handleCommonMethodCalls);

Future _handleCommonMethodCalls(MethodCall methodCall) async {
  switch (methodCall.method) {
    case 'error':
      lastError.value = methodCall.arguments;
      break;
  }
}

Future<bool> checkArAvailability() async {
  try {
    return await _commonChannel.invokeMethod('isAvailable') &&
        await Permission.camera.request() == PermissionStatus.granted;
  } catch (_) {
    return false;
  }
}

typedef ArViewCreatedCallback = void Function(ArViewController controller);
typedef ArHitCallback = void Function(ARHitResult result);
typedef ArTrackingCallback = void Function(ARTrackingState state);
typedef ArNodeTapCallback = void Function(String name);

class ArView extends StatefulWidget {
  const ArView({
    super.key,
    required this.onArViewCreated,
    required this.onPlaneTap,
    required this.controller,
    this.onTrackingState,
    this.onNodeTap,
    this.width = 300,
    this.height = 300,
  });

  final TransformArViewController controller;
  final double width;
  final double height;
  final ArViewCreatedCallback onArViewCreated;
  final ArHitCallback onPlaneTap;
  final ArTrackingCallback? onTrackingState;
  final ArNodeTapCallback? onNodeTap;

  @override
  ArViewState createState() => ArViewState();
}

class ArViewState extends State<ArView> {
  static const String _viewType = 'com.paidviewpoint.ar';

  @override
  Widget build(BuildContext context) {
    final Widget platformView = defaultTargetPlatform == TargetPlatform.android
        ? AndroidView(
            viewType: _viewType,
            onPlatformViewCreated: _onPlatformViewCreated,
          )
        : UiKitView(
            viewType: _viewType,
            onPlatformViewCreated: _onPlatformViewCreated,
          );
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: platformView,
    );
  }

  void _onPlatformViewCreated(int id) =>
      widget.onArViewCreated(ArViewController(id, widget));
}

class ArViewController {
  final ArView widget;
  ArViewController(int id, this.widget) {
    _channel = MethodChannel('ar_$id');
    _channel.setMethodCallHandler(_handleMethodCalls);
  }

  late MethodChannel _channel;

  Future<dynamic> _handleMethodCalls(MethodCall methodCall) async {
    switch (methodCall.method) {
      case 'onTrackingState':
        widget.onTrackingState
            ?.call(ARTrackingState.fromJson(methodCall.arguments));
        break;
      case 'onPlaneTap':
        widget.onPlaneTap(ARHitResult.fromJson(methodCall.arguments));
        break;
      case 'onNodeTap':
        final name = (methodCall.arguments as Map?)?['name'] as String?;
        if (name != null) widget.onNodeTap?.call(name);
        break;
    }
  }

  /// Tell the native renderer to load a glb (Filament/gltfio on Android,
  /// SceneKit + GLTFKit2 on iOS). Asset path is resolved natively against
  /// Flutter's bundled assets.
  Future<void> loadModel(String assetPath, {double fitMeters = 2.0}) {
    return _channel.invokeMethod('loadModel', {
      'modelPath': assetPath,
      'fitMeters': fitMeters,
    });
  }

  /// Hide the subtree under the named glTF node on the placed model.
  /// No-op until the user has tapped a wall to place; returns false in
  /// that case. The hidden subtree is retained natively so
  /// [restoreNode] can put it back.
  Future<bool> removeNode(String name) async {
    final r = await _channel.invokeMethod<bool>('removeNode', {'name': name});
    return r ?? false;
  }

  Future<bool> restoreNode(String name) async {
    final r = await _channel.invokeMethod<bool>('restoreNode', {'name': name});
    return r ?? false;
  }

  Future<List<String>> listNodes() async {
    final r = await _channel.invokeMethod<List<dynamic>>('listNodes');
    return r?.cast<String>() ?? const [];
  }
}
