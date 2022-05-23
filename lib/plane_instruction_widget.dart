import 'package:flutter/material.dart';

class PlaneInstructionWidget extends StatelessWidget {
  final VoidCallback callback;
  const PlaneInstructionWidget({Key? key, required this.callback})
      : super(key: key);

  @override
  Widget build(BuildContext context) => AlertDialog(
      insetPadding: EdgeInsets.zero,
      titlePadding: EdgeInsets.zero,
      content: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
              'Point your camera at the wall, then move around to detect vertical planes, then tap on detected plane'),
          Image.asset('assets/sceneform_hand_phone.png'),
          TextButton(onPressed: callback, child: const Text('Ok'))
        ],
      ));
}
