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
  final Set<String> _removed = {};

  @override
  void initState() {
    super.initState();
    // Both platforms render the glb natively now (Filament/gltfio on
    // Android, SceneKit + GLTFKit2 on iOS), so an asset path is all the
    // controller needs.
    _controller.modelAssetPath = 'assets/out.glb';
    _controller.onNodeTap = (name) => _confirmRemove(context, name);
  }

  Future<void> _confirmRemove(BuildContext context, String name) async {
    final confirmed = await _showNodeModal(context, name);
    if (confirmed != true) return;
    if (await _controller.removeNode(name) && mounted) {
      setState(() => _removed.add(name));
    }
  }

  Future<void> _restore(String name) async {
    if (await _controller.restoreNode(name) && mounted) {
      setState(() => _removed.remove(name));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        children: [
          TransformArView(controller: _controller),
          if (_removed.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: _RemovedNodesBar(names: _removed, onRestore: _restore),
            ),
        ],
      ),
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
  final Set<String> _removed = {};

  @override
  void initState() {
    super.initState();
    _controller.modelAssetPath = 'assets/out.glb';
    _controller.onNodeTap = (name) => _confirmRemove(context, name);
  }

  Future<void> _confirmRemove(BuildContext context, String name) async {
    final confirmed = await _showNodeModal(context, name);
    if (confirmed != true) return;
    if (await _controller.removeNode(name) && mounted) {
      setState(() => _removed.add(name));
    }
  }

  Future<void> _restore(String name) async {
    if (await _controller.restoreNode(name) && mounted) {
      setState(() => _removed.remove(name));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        children: [
          TransformThreeDView(controller: _controller),
          if (_removed.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: _RemovedNodesBar(names: _removed, onRestore: _restore),
            ),
        ],
      ),
    );
  }
}

Future<bool?> _showNodeModal(BuildContext context, String name) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Node'),
      content: Text(name),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
}

class _RemovedNodesBar extends StatelessWidget {
  final Set<String> names;
  final Future<void> Function(String) onRestore;
  const _RemovedNodesBar({required this.names, required this.onRestore});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final n in names)
              InputChip(
                label: Text(n),
                deleteIcon: const Icon(Icons.undo, size: 18),
                onDeleted: () => onRestore(n),
              ),
          ],
        ),
      ),
    );
  }
}
