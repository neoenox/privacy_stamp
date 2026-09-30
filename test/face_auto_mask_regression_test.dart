import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:privacy_stamp/features/redaction/detection/detector_service.dart';
import 'package:privacy_stamp/features/redaction/detection/face_detector.dart';
import 'package:privacy_stamp/features/redaction/models/redaction_models.dart';
import 'package:privacy_stamp/features/redaction/presentation/stamp_controller.dart';

class _FakeFaceDetector implements FaceRegionDetector {
  const _FakeFaceDetector(this.regions);

  final List<DetectionRegion> regions;

  @override
  Future<DetectionResult> detect(Uint8ListImageInput input) async =>
      DetectionResult(regions: regions, outcome: DetectionOutcome.success);
}

class _ThrowingFaceDetector implements FaceRegionDetector {
  const _ThrowingFaceDetector();

  @override
  Future<DetectionResult> detect(Uint8ListImageInput input) async =>
      throw StateError('no model');
}

void main() {
  group('face auto-stamp', () {
    test('DetectionService merges face candidates with text hits', () async {
      final service = DetectionService(
        faceDetector: _FakeFaceDetector([
          DetectionRegion(
            id: 'face-0',
            kind: DetectionKind.face,
            normalizedRect: const NormalizedRect(.1, .1, .2, .2),
          ),
        ]),
      );
      final regions = await service.inspect(
        Uint8ListImageInput(Uint8List.fromList([1, 2, 3])),
      );
      expect(regions, hasLength(1));
      expect(regions.single.kind, DetectionKind.face);
    });

    test('face detector failure degrades to empty, not throw', () async {
      final service = DetectionService(
        faceDetector: const _ThrowingFaceDetector(),
      );
      final regions = await service.inspect(
        Uint8ListImageInput(Uint8List.fromList([1, 2, 3])),
      );
      expect(regions, isEmpty);
    });

    test(
      'MlKitFaceDetector returns empty without throwing off-device',
      () async {
        // No platform plugin on the test host: must degrade gracefully.
        final detector = MlKitFaceDetector();
        final regions = await detector.detect(
          Uint8ListImageInput(Uint8List.fromList([0, 1, 2, 3])),
        );
        expect(regions.regions, isEmpty);
      },
    );

    test('NoopFaceDetector returns empty', () async {
      final regions = await const NoopFaceDetector().detect(
        Uint8ListImageInput(Uint8List.fromList([1])),
      );
      expect(regions.regions, isEmpty);
    });

    test('controller surfaces automatic stamps and can clear them', () async {
      final controller = StampController(
        picker: const _Picker(),
        detector: _Gateway(
          DetectionService(
            faceDetector: _FakeFaceDetector([
              DetectionRegion(
                id: 'face-0',
                kind: DetectionKind.face,
                normalizedRect: const NormalizedRect(.1, .1, .2, .2),
              ),
            ]),
          ),
        ),
        exporter: (source, stamps) => Uint8List.fromList(<int>[1]),
        saver: _Saver(),
        history: const _History(),
      );
      await controller.pickImage();

      expect(controller.automaticCount, 1);
      expect(controller.stamps, hasLength(1));
      expect(controller.stamps.single.isAutomatic, isTrue);

      controller.clearAutomaticDetections();
      expect(controller.automaticCount, 0);
      expect(controller.stamps, isEmpty);
    });

    test('automatic stamps are included in export', () async {
      List<Stamp>? exported;
      final controller = StampController(
        picker: const _Picker(),
        detector: _Gateway(
          DetectionService(
            faceDetector: _FakeFaceDetector([
              DetectionRegion(
                id: 'face-0',
                kind: DetectionKind.face,
                normalizedRect: const NormalizedRect(.1, .1, .2, .2),
              ),
            ]),
          ),
        ),
        exporter: (source, stamps) {
          exported = stamps;
          return Uint8List.fromList(<int>[1]);
        },
        saver: _Saver(),
        history: const _History(),
      );
      await controller.pickImage();
      final result = await controller.exportImage();
      expect(result, ExportResult.exported);
      expect(exported, hasLength(1));
      expect(exported!.single.isAutomatic, isTrue);
    });
  });
}

class _Picker implements ImagePickerGateway {
  const _Picker();

  @override
  Future<PickedImage?> pick() async => const PickedImage(
    bytes: <int>[1, 2, 3],
    name: 'face.png',
    imageSize: PixelSize(100, 100),
  );
}

class _Gateway implements DetectionGateway {
  _Gateway(this.service);

  final DetectionService service;

  @override
  Future<List<DetectionRegion>> inspect(Uint8ListImageInput input) =>
      service.inspect(input);
}

class _Saver implements ImageSaverGateway {
  @override
  Future<bool> save(Uint8List bytes, {required String fileName}) async => true;
}

class _History implements ExportHistoryGateway {
  const _History();

  @override
  Future<int> readCount() async => 0;

  @override
  Future<void> recordExport() async {}
}
