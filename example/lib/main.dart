import 'dart:async';

import 'package:ar/ar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await checkArAvailability();
  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitDown, DeviceOrientation.portraitUp]);
  runApp(const MaterialApp(home: DemoPage()));
}

class DemoPage extends StatefulWidget {
  const DemoPage({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => DemoPageState();
}

class DemoPageState extends State<DemoPage> {
  @override
  Widget build(BuildContext context) => SafeArea(
          child: Stack(children: [
        TransformArView(
          controller: TransformArViewController(
            pixelsPerMeter: 600,
            size: const Size(300, 300),
            transformKey: GlobalKey(),
            planeDetected: ValueNotifier(false),
            transform: ValueNotifier<Matrix4?>(null),
          ),
          child: Container(
            color: Colors.grey.withOpacity(0.5),
            child: const Align(
              alignment: Alignment.center,
              child: Text('AR View'),
            ),
          ),
        )
      ]));
}
