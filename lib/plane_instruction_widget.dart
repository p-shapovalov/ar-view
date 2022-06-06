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
              'To display the shelf point your phone camera at an unobstructed wall. Pan your phone to detect vertical planes. Tap on the planes to display the shelf. Tap Ok to start',
              textAlign: TextAlign.center),
          TextButton(onPressed: callback, child: const Text('Ok'))
        ],
      ));
}
