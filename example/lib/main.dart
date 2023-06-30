import 'dart:async';
import 'dart:math' as math;

import 'package:ar/ar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

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
              transform: ValueNotifier<Matrix4?>(null),
              mapPlane: (Matrix4 plane, Matrix4 finalTransform) {
                final p = plane.clone();

                final tr = p.getTranslation();
                tr.y = 0;
                p.setTranslation(tr);
                // set as parallel to the surface
                p.rotateX(math.pi / 2);
                p.rotateY(-math.pi / 2);
                // p.rotateZ(-math.pi);

                final up = vm.Vector3(0.0, 1.0, 0.0);

                // vm.Matrix3 finalRotation = (finalTransform.clone()
                //     // ..rotateX(math.pi / 2)
                //     )
                //     .getRotation();
                // // face to camera - flip if needed
                // if (finalRotation.forward.z > 0) p.rotateY(math.pi);
                // turn yAxis to up
                // final angle = p.up.angleTo(up);
                // p.rotateZ(angle);
                // if (p.up.angleTo(up) > 0.01) p.rotateZ(-2 * angle);

                return p;
              }),
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
