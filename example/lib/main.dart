import 'package:ar/ar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await checkArAvailability();
  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitDown, DeviceOrientation.portraitUp]);
  runApp(const MaterialApp(home: MainPage()));
}

class MainPage extends StatelessWidget {
  const MainPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ArPage()),
              ),
              child: const Text('AR'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ThreeDPage()),
              ),
              child: const Text('3D'),
            ),
          ],
        ),
      ),
    );
  }
}

class ArPage extends StatefulWidget {
  const ArPage({super.key});

  @override
  State<ArPage> createState() => _ArPageState();
}

class _ArPageState extends State<ArPage> {
  final _controller = TransformArViewController();

  @override
  void initState() {
    super.initState();
    // Both platforms render the glb natively now (Filament/gltfio on
    // Android, SceneKit + GLTFKit2 on iOS), so an asset path is all the
    // controller needs.
    _controller.modelAssetPath = 'assets/out.glb';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: TransformArView(controller: _controller),
    );
  }
}

class ThreeDPage extends StatefulWidget {
  const ThreeDPage({super.key});

  @override
  State<ThreeDPage> createState() => _ThreeDPageState();
}

class _ThreeDPageState extends State<ThreeDPage> {
  final _controller = TransformThreeDViewController();

  @override
  void initState() {
    super.initState();
    _controller.modelAssetPath = 'assets/out.glb';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: TransformThreeDView(controller: _controller),
    );
  }
}
