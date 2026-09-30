import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:privacy_stamp/features/redaction/models/redaction_models.dart';
import 'package:privacy_stamp/features/redaction/presentation/stamp_controller.dart';

void main() {
  test('keeps manual stamps separate from analysis results', () async {
    final detector = _FakeDetector(
      result: [
        DetectionRegion(
          id: 'automatic-1',
          kind: DetectionKind.email,
          normalizedRect: const NormalizedRect(.1, .1, .2, .1),
        ),
      ],
    );
    final controller = StampController(
      picker: _FakePicker(const _PickedImage()),
      detector: detector,
      exporter: (source, stamps) => Uint8List.fromList([1]),
      saver: _FakeSaver(),
      history: _FakeHistory(),
    );

    await controller.pickImage();
    controller.addManualStamp();

    expect(controller.detections, hasLength(1));
    expect(controller.manualStamps, hasLength(1));
    expect(controller.stamps, hasLength(2));
    expect(controller.manualStamps.single.isAutomatic, isFalse);
  });

  test('stale detection cannot replace a reset image state', () async {
    final detectionCompleter = Completer<List<DetectionRegion>>();
    final controller = StampController(
      picker: _FakePicker(const _PickedImage()),
      detector: _CompleterDetector(detectionCompleter),
      exporter: (source, stamps) => Uint8List.fromList([1]),
      saver: _FakeSaver(),
      history: _FakeHistory(),
    );

    final pickFuture = controller.pickImage();
    await Future<void>.delayed(Duration.zero);
    controller.reset();
    detectionCompleter.complete(const []);
    await pickFuture;

    expect(controller.bytes, isNull);
    expect(controller.stamps, isEmpty);
    expect(controller.isBusy, isFalse);
  });

  test('stale image A detection cannot replace newer image B state', () async {
    final imageADetection = Completer<List<DetectionRegion>>();
    final controller = StampController(
      picker: _SequencePicker([
        const _PickedImage(),
        const PickedImage(
          bytes: [4, 5, 6],
          name: 'image-b.png',
          imageSize: PixelSize(200, 100),
        ),
      ]),
      detector: _QueueDetector([
        imageADetection.future,
        Future.value([
          DetectionRegion(
            id: 'automatic-b',
            kind: DetectionKind.email,
            normalizedRect: const NormalizedRect(.2, .2, .2, .1),
          ),
        ]),
      ]),
      exporter: (source, stamps) => Uint8List.fromList([1]),
      saver: _FakeSaver(),
      history: _FakeHistory(),
    );

    final imageAFuture = controller.pickImage();
    await Future<void>.delayed(Duration.zero);
    controller.reset();
    await controller.pickImage();
    imageADetection.complete(const []);
    await imageAFuture;

    expect(controller.fileName, 'image-b.png');
    expect(controller.detections.single.id, 'automatic-b');
  });

  test(
    'does not start a second export while the first saver is busy',
    () async {
      final saver = _BlockingSaver();
      final controller = StampController(
        picker: _FakePicker(const _PickedImage()),
        detector: _FakeDetector(result: const []),
        exporter: (source, stamps) => Uint8List.fromList([1]),
        saver: saver,
        history: _FakeHistory(),
      );
      await controller.pickImage();
      controller.addManualStamp();

      final first = controller.exportImage();
      final second = controller.exportImage();
      expect(await second, ExportResult.busy);

      saver.complete(true);
      expect(await first, ExportResult.exported);
      expect(saver.calls, 1);
    },
  );

  test(
    'supports manual mask move, resize, and removal without touching detections',
    () async {
      final controller = StampController(
        picker: _FakePicker(const _PickedImage()),
        detector: _FakeDetector(result: const []),
        exporter: (source, stamps) => Uint8List.fromList([1]),
        saver: _FakeSaver(),
        history: _FakeHistory(),
      );
      await controller.pickImage();
      controller.addManualStamp();
      final stamp = controller.manualStamps.single;
      final original = stamp.rect;

      controller.moveManualStamp(stamp.id, const Offset(.1, .05));
      expect(
        controller.manualStamps.single.rect.left,
        greaterThan(original.left),
      );
      expect(
        controller.manualStamps.single.rect.top,
        greaterThan(original.top),
      );

      final moved = controller.manualStamps.single.rect;
      controller.resizeManualStamp(stamp.id, const Offset(.1, .1));
      expect(
        controller.manualStamps.single.rect.width,
        greaterThan(moved.width),
      );
      expect(
        controller.manualStamps.single.rect.height,
        greaterThan(moved.height),
      );

      controller.removeManualStamp(stamp.id);
      expect(controller.manualStamps, isEmpty);
      expect(controller.detections, isEmpty);
    },
  );

  test('does not notify or apply stale detection after dispose', () async {
    final detectionCompleter = Completer<List<DetectionRegion>>();
    final controller = StampController(
      picker: _FakePicker(const _PickedImage()),
      detector: _CompleterDetector(detectionCompleter),
      exporter: (source, stamps) => Uint8List.fromList([1]),
      saver: _FakeSaver(),
      history: _FakeHistory(),
    );

    final pickFuture = controller.pickImage();
    await Future<void>.delayed(Duration.zero);
    controller.dispose();
    detectionCompleter.complete(const []);

    await expectLater(pickFuture, completes);
  });
}

class _PickedImage extends PickedImage {
  const _PickedImage()
    : super(
        bytes: const [1, 2, 3],
        name: 'test.png',
        imageSize: const PixelSize(100, 100),
      );
}

class _FakePicker implements ImagePickerGateway {
  const _FakePicker(this.image);
  final PickedImage image;
  @override
  Future<PickedImage?> pick() async => image;
}

class _SequencePicker implements ImagePickerGateway {
  _SequencePicker(this.images);
  final List<PickedImage> images;

  @override
  Future<PickedImage?> pick() async => images.removeAt(0);
}

class _FakeDetector implements DetectionGateway {
  _FakeDetector({required this.result});
  final List<DetectionRegion> result;
  @override
  Future<List<DetectionRegion>> inspect(Uint8ListImageInput input) async =>
      result;
}

class _CompleterDetector implements DetectionGateway {
  _CompleterDetector(this.completer);
  final Completer<List<DetectionRegion>> completer;
  @override
  Future<List<DetectionRegion>> inspect(Uint8ListImageInput input) =>
      completer.future;
}

class _QueueDetector implements DetectionGateway {
  _QueueDetector(this.results);
  final List<Future<List<DetectionRegion>>> results;

  @override
  Future<List<DetectionRegion>> inspect(Uint8ListImageInput input) =>
      results.removeAt(0);
}

class _FakeSaver implements ImageSaverGateway {
  @override
  Future<bool> save(Uint8List bytes, {required String fileName}) async => true;
}

class _BlockingSaver implements ImageSaverGateway {
  final Completer<bool> _completer = Completer<bool>();
  int calls = 0;

  @override
  Future<bool> save(Uint8List bytes, {required String fileName}) {
    calls++;
    return _completer.future;
  }

  void complete(bool saved) => _completer.complete(saved);
}

class _FakeHistory implements ExportHistoryGateway {
  @override
  Future<int> readCount() async => 0;

  @override
  Future<void> recordExport() async {}
}
