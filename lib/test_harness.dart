import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as image;

import 'features/redaction/models/redaction_models.dart';
import 'features/redaction/presentation/stamp_controller.dart';

class TestHarness extends StatefulWidget {
  const TestHarness({super.key, required this.controller, required this.child});

  final StampController controller;
  final Widget child;

  @override
  State<TestHarness> createState() => _TestHarnessState();
}

class _TestHarnessState extends State<TestHarness> {
  late final StampController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller;
    _loadFixture();
  }

  Future<void> _loadFixture() async {
    try {
      final bytes = await rootBundle.load(
        'test/fixtures/synthetic-high-res-avd.jpg',
      );
      final data = bytes.buffer.asUint8List();
      final decoded = image.decodeImage(data);
      if (decoded == null) {
        throw const FormatException('Synthetic fixture could not be decoded.');
      }
      final size = PixelSize(decoded.width, decoded.height);
      // Test harness intentionally exercises the acceptance-only injection API.
      // ignore: invalid_use_of_visible_for_testing_member
      _controller.loadImageForTesting(data, 'synthetic-high-res-avd.jpg', size);
      if (!mounted) return;
      setState(() {
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    }
  }

  StampController get controller => _controller;

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return MaterialApp(
        home: Scaffold(body: Center(child: Text('Harness error: $_error'))),
      );
    }
    return widget.child;
  }
}
