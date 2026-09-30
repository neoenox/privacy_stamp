import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:privacy_stamp/features/redaction/export/redaction_exporter.dart';
import 'package:privacy_stamp/features/redaction/models/redaction_models.dart';
import 'package:privacy_stamp/features/redaction/presentation/stamp_controller.dart';
import 'package:privacy_stamp/main.dart';

import '../tool/acceptance/image_metadata.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  _bootstrap('binding-ready');

  testWidgets(
    'A: 48MP GPS fixture selects, zooms, pans, masks, and exports metadata-free PNG',
    (tester) async {
      _milestone('A:start');
      final fixture = await _fixture();
      _milestone('A:fixture-inspected');
      final source = fixture.bytes;
      final sourceSize = fixture.imageSize;
      final saver = _CapturingSaver();
      final controller = _controller(
        picker: _FixturePicker(source, sourceSize, 'A'),
        saver: saver,
        diagnosticLabel: 'A',
      );

      await tester.pumpWidget(
        MaterialApp(home: StampHomePage(controller: controller)),
      );
      _milestone('A:widget-pumped');
      await tester.tap(find.widgetWithText(FilledButton, '画像を選ぶ'));
      _milestone('A:picker-tapped');
      _milestone(
        'A:post-tap-state hasImage=${controller.hasImage} '
        'busy=${controller.isBusy} size=${controller.imageSize}',
      );
      await _pumpBounded(
        tester,
        frames: 50,
        diagnosticLabel: 'A:image-selection',
      );
      _milestone('A:image-selection-settled');

      expect(controller.imageSize, const PixelSize(6000, 8000));
      expect(find.byType(Image), findsOneWidget);

      final canvas = find.byKey(const ValueKey('image-editor-canvas'));
      expect(canvas, findsOneWidget);
      await tester.tapAt(tester.getCenter(canvas));
      await _pumpBounded(tester);
      _milestone('A:mask-added');
      expect(controller.manualStamps, hasLength(1));

      final viewer = find.byKey(
        const ValueKey('image-editor-interactive-viewer'),
      );
      expect(viewer, findsOneWidget);
      final center = tester.getCenter(viewer);
      final left = await tester.startGesture(
        center - const Offset(30, 0),
        pointer: 1,
      );
      final right = await tester.startGesture(
        center + const Offset(30, 0),
        pointer: 2,
      );
      await left.moveTo(center - const Offset(90, 0));
      await right.moveTo(center + const Offset(90, 0));
      await tester.pump();
      await left.up();
      await right.up();
      await tester.drag(viewer, const Offset(24, 18));
      await tester.pump();
      _milestone('A:zoom-pan-complete');
      expect(tester.takeException(), isNull);

      await tester.tap(find.widgetWithText(FilledButton, '書き出す'));
      await _pumpBounded(tester, frames: 30);
      _milestone('A:export-confirmation-visible');
      await tester.tap(find.widgetWithText(FilledButton, '確認して書き出す'));
      _milestone('A:export-confirmed');
      await _pumpBounded(tester, frames: 100);
      _milestone('A:export-pump-complete');

      expect(controller.exportCount, 1);
      final output = saver.bytes;
      expect(output, isNotNull);
      final outputInfo = await _inspectBytes(output!, 'synthetic-output.png');
      _milestone('A:output-inspected');
      expect(outputInfo.format, 'PNG');
      expect(outputInfo.pixels, sourceSize.width * sourceSize.height);
      expect(outputInfo.gpsPresent, isFalse);
      expect(outputInfo.metadataContainerPresent, isFalse);
      expect(tester.takeException(), isNull);
      _milestone('A:pass');
    },
  );
  _bootstrap('test-a-registered');

  testWidgets('B: picker cancellation leaves the app usable', (tester) async {
    _milestone('B:start');
    final controller = _controller(
      picker: const _NoopPicker('B'),
      saver: _CapturingSaver(),
      diagnosticLabel: 'B',
    );
    await tester.pumpWidget(
      MaterialApp(home: StampHomePage(controller: controller)),
    );

    await tester.tap(find.widgetWithText(FilledButton, '画像を選ぶ'));
    await _pumpBounded(tester);

    expect(controller.hasImage, isFalse);
    expect(controller.isBusy, isFalse);
    expect(find.widgetWithText(FilledButton, '画像を選ぶ'), findsOneWidget);
    expect(tester.takeException(), isNull);
    _milestone('B:pass');
  });
  _bootstrap('test-b-registered');

  testWidgets(
    'C: discard and lifecycle pause/resume leave no stale editor state',
    (tester) async {
      _milestone('C:start');
      final fixture = await _fixture();
      final controller = _controller(
        picker: _FixturePicker(fixture.bytes, fixture.imageSize, 'C'),
        saver: _CapturingSaver(),
        diagnosticLabel: 'C',
      );
      await tester.pumpWidget(
        MaterialApp(home: StampHomePage(controller: controller)),
      );
      await tester.tap(find.widgetWithText(FilledButton, '画像を選ぶ'));
      await _pumpBounded(tester, frames: 50);
      expect(controller.hasImage, isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.tap(find.widgetWithText(OutlinedButton, '別の画像'));
      await _pumpBounded(tester);
      expect(controller.hasImage, isFalse);
      expect(controller.stamps, isEmpty);
      expect(controller.isBusy, isFalse);
      expect(find.widgetWithText(FilledButton, '画像を選ぶ'), findsOneWidget);
      expect(tester.takeException(), isNull);
      _milestone('C:pass');
    },
  );
  _bootstrap('test-c-registered');
  _bootstrap('registration-complete');
}

void _bootstrap(String name) {
  final now = DateTime.now().toUtc().toIso8601String();
  // Bootstrap markers are diagnostics only and never count as acceptance.
  // ignore: avoid_print
  print('ACCEPTANCE_BOOTSTRAP $now $name');
}

void _milestone(String name) {
  final now = DateTime.now().toUtc().toIso8601String();
  // ignore: avoid_print
  print('ACCEPTANCE_MILESTONE $now $name');
}

StampController _controller({
  required ImagePickerGateway picker,
  required ImageSaverGateway saver,
  required String diagnosticLabel,
}) => StampController(
  picker: picker,
  detector: _NoopDetector(diagnosticLabel),
  exporter: const RedactionExporter().encodeAsync,
  saver: saver,
  history: const _InMemoryHistory(),
);

Future<({Uint8List bytes, PixelSize imageSize})> _fixture() async {
  final fixture = await rootBundle.load(
    'test/fixtures/synthetic-high-res-avd.jpg',
  );
  final source = fixture.buffer.asUint8List();
  expect(source, isNotEmpty);
  return (bytes: source, imageSize: const PixelSize(6000, 8000));
}

Future<AcceptanceImageMetadata> _inspectBytes(
  Uint8List bytes,
  String name,
) async {
  final directory = await Directory.systemTemp.createTemp(
    'privacy-stamp-acceptance-',
  );
  final file = File('${directory.path}/$name');
  try {
    await file.writeAsBytes(bytes);
    return await inspectAcceptanceImage(file.path);
  } finally {
    await directory.delete(recursive: true);
  }
}

Future<void> _pumpBounded(
  WidgetTester tester, {
  int frames = 30,
  String? diagnosticLabel,
}) async {
  if (diagnosticLabel != null) {
    _milestone('$diagnosticLabel:pump-start frames=$frames');
  }
  for (var i = 0; i < frames; i++) {
    final traceFrame =
        diagnosticLabel != null &&
        (i < 3 || i == 4 || i == 9 || i == frames - 1);
    if (traceFrame) {
      _milestone('$diagnosticLabel:frame-${i + 1}-start');
    }
    await tester.pump(const Duration(milliseconds: 100));
    if (traceFrame) {
      _milestone('$diagnosticLabel:frame-${i + 1}-done');
    }
  }
  if (diagnosticLabel != null) {
    _milestone('$diagnosticLabel:pump-complete');
  }
}

class _CapturingSaver implements ImageSaverGateway {
  Uint8List? bytes;

  @override
  Future<bool> save(Uint8List bytes, {required String fileName}) async {
    this.bytes = bytes;
    return true;
  }
}

class _FixturePicker implements ImagePickerGateway {
  const _FixturePicker(this.bytes, this.imageSize, this.diagnosticLabel);

  final Uint8List bytes;
  final PixelSize imageSize;
  final String diagnosticLabel;

  @override
  Future<PickedImage?> pick() async {
    _milestone('$diagnosticLabel:picker-enter');
    final picked = PickedImage(
      bytes: bytes,
      name: 'synthetic-high-res-avd.jpg',
      imageSize: imageSize,
    );
    _milestone('$diagnosticLabel:picker-return');
    return picked;
  }
}

class _NoopPicker implements ImagePickerGateway {
  const _NoopPicker(this.diagnosticLabel);

  final String diagnosticLabel;

  @override
  Future<PickedImage?> pick() async {
    _milestone('$diagnosticLabel:picker-enter');
    _milestone('$diagnosticLabel:picker-return-null');
    return null;
  }
}

class _NoopDetector implements DetectionGateway {
  const _NoopDetector(this.diagnosticLabel);

  final String diagnosticLabel;

  @override
  Future<List<DetectionRegion>> inspect(Uint8ListImageInput input) async {
    _milestone('$diagnosticLabel:detector-enter');
    _milestone('$diagnosticLabel:detector-return');
    return const [];
  }
}

class _InMemoryHistory implements ExportHistoryGateway {
  const _InMemoryHistory();

  @override
  Future<int> readCount() async => 0;

  @override
  Future<void> recordExport() async {}
}
