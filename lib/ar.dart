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
typedef ArHitCallback = void Function(ARHitResult controller);
typedef ArFrameCallback = void Function(ARFrameResult controller);

class ArView extends StatefulWidget {
  const ArView(
      {super.key,
      required this.onArViewCreated,
      required this.onPlaneTap,
      required this.onFrame,
      required this.controller,
      this.width = 300,
      this.height = 300});

  final TransformArViewController controller;
  final double width;
  final double height;
  final ArViewCreatedCallback onArViewCreated;
  final ArHitCallback onPlaneTap;
  final ArFrameCallback onFrame;

  @override
  ArViewState createState() => ArViewState();
}

class ArViewState extends State<ArView> with WidgetsBindingObserver {
  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    super.initState();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() {
        widget.controller.reset();
      });
    }

    super.didChangeAppLifecycleState(state);
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return SizedBox(
          width: widget.width,
          height: widget.height,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              AndroidView(
                viewType: 'com.paidviewpoint.ar',
                onPlatformViewCreated: _onPlatformViewCreated,
              )
            ],
          ));
    } else {
      return SizedBox(
          width: widget.width,
          height: widget.height,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              UiKitView(
                viewType: 'com.paidviewpoint.ar',
                onPlatformViewCreated: _onPlatformViewCreated,
              )
            ],
          ));
    }
  }

  void _onPlatformViewCreated(int id) =>
      widget.onArViewCreated(ArViewController(id, widget));

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
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
      case 'onFrame':
        widget.onFrame(ARFrameResult.fromJson(methodCall.arguments));
        break;
      case 'onPlaneTap':
        widget.onPlaneTap(ARHitResult.fromJson(methodCall.arguments));
        break;
    }
  }
}
