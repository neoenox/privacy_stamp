import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:privacy_stamp/features/redaction/detection/detector_service.dart';
import 'package:privacy_stamp/features/redaction/models/redaction_models.dart';
import 'package:privacy_stamp/features/redaction/presentation/stamp_controller.dart';

class _FakeFaceDetector implements FaceRegionDetector {
  const _FakeFaceDetector(this.result);

  final DetectionResult result;

  @override
  Future<DetectionResult> detect(Uint8ListImageInput input) async => result;
}

class _ThrowingFaceDetector implements FaceRegionDetector {
  const _ThrowingFaceDetector();

  @override
  Future<DetectionResult> detect(Uint8ListImageInput input) async =>
      throw StateError('no model');
}

void main() {
  group('DetectionResult', () {
    test('empty has empty regions', () {
      final result = DetectionResult.empty();
      expect(result.regions, isEmpty);
      expect(result.outcome, DetectionOutcome.empty);
      expect(result.isEmpty, isTrue);
      expect(result.isSuccess, isFalse);
      expect(result.isException, isFalse);
    });

    test('success has regions and correct outcome', () {
      final result = DetectionResult(
        regions: [
          DetectionRegion(
            id: 'face-0',
            kind: DetectionKind.face,
            normalizedRect: const NormalizedRect(.1, .1, .2, .2),
          ),
        ],
        outcome: DetectionOutcome.success,
        width: 1024,
        height: 768,
        faceCount: 1,
      );
      expect(result.regions, hasLength(1));
      expect(result.outcome, DetectionOutcome.success);
      expect(result.isEmpty, isFalse);
      expect(result.isSuccess, isTrue);
      expect(result.isException, isFalse);
      expect(result.faceCount, 1);
    });

    test('exception carries error info', () {
      final result = DetectionResult.exception(error: 'ML Kit failed');
      expect(result.regions, isEmpty);
      expect(result.outcome, DetectionOutcome.exception);
      expect(result.isException, isTrue);
      expect(result.error, 'ML Kit failed');
    });
  });

  group('DetectionService diagnostic', () {
    test('stores lastSummary after inspect', () async {
      final service = DetectionService(
        faceDetector: _FakeFaceDetector(
          DetectionResult(
            regions: [
              DetectionRegion(
                id: 'face-0',
                kind: DetectionKind.face,
                normalizedRect: const NormalizedRect(.1, .1, .2, .2),
              ),
            ],
            outcome: DetectionOutcome.success,
            faceCount: 1,
          ),
        ),
      );

      final regions = await service.inspect(
        Uint8ListImageInput(Uint8List.fromList([1, 2, 3])),
      );
      expect(regions, hasLength(1));
      expect(service.lastSummary, isNotNull);
      expect(service.lastSummary!.faces.isSuccess, isTrue);
      expect(service.lastSummary!.faces.faceCount, 1);
    });

    test('stores exception summary when detector fails', () async {
      final service = DetectionService(
        faceDetector: const _ThrowingFaceDetector(),
      );

      final regions = await service.inspect(
        Uint8ListImageInput(Uint8List.fromList([1, 2, 3])),
      );
      expect(regions, isEmpty);
      expect(service.lastSummary, isNotNull);
      expect(service.lastSummary!.faces.isException, isTrue);
      expect(service.lastSummary!.hasFaceException, isTrue);
    });

    test('inspectWithDiagnostics returns stored summary', () async {
      final service = DetectionService(
        faceDetector: _FakeFaceDetector(
          DetectionResult(
            regions: [],
            outcome: DetectionOutcome.empty,
          ),
        ),
      );

      await service.inspect(Uint8ListImageInput(Uint8List.fromList([1])));
      final summary = await service.inspectWithDiagnostics(
        Uint8ListImageInput(Uint8List.fromList([1])),
      );
      expect(summary.faces.outcome, DetectionOutcome.empty);
    });
  });

  group('DetectionServiceGateway diagnostic', () {
    test('exposes lastSummary from service', () async {
      final service = DetectionService(
        faceDetector: _FakeFaceDetector(
          DetectionResult(
            regions: [
              DetectionRegion(
                id: 'face-0',
                kind: DetectionKind.face,
                normalizedRect: const NormalizedRect(.1, .1, .2, .2),
              ),
            ],
            outcome: DetectionOutcome.success,
            faceCount: 1,
          ),
        ),
      );
      final gateway = DetectionServiceGateway(detector: service);

      await gateway.inspect(Uint8ListImageInput(Uint8List.fromList([1])));
      expect(gateway.lastSummary, isNotNull);
      expect(gateway.lastSummary!.faces.isSuccess, isTrue);
    });
  });

  group('controller with detection', () {
    test('surfaces automatic stamps from real detector', () async {
      final controller = StampController(
        picker: const _Picker(),
        detector: DetectionServiceGateway(
          detector: DetectionService(
            faceDetector: _FakeFaceDetector(
              DetectionResult(
                regions: [
                  DetectionRegion(
                    id: 'face-0',
                    kind: DetectionKind.face,
                    normalizedRect: const NormalizedRect(.1, .1, .2, .2),
                  ),
                ],
                outcome: DetectionOutcome.success,
                faceCount: 1,
              ),
            ),
          ),
        ),
        exporter: (source, stamps) => Uint8List.fromList(<int>[1]),
        saver: _Saver(),
        history: const _History(),
      );
      await controller.pickImage();

      expect(controller.automaticCount, 1);
      expect(controller.lastDetectionSummary, isNotNull);
      expect(controller.lastDetectionSummary!.faces.isSuccess, isTrue);
    });

    test('detectionEmpty when detector returns no faces', () async {
      final controller = StampController(
        picker: const _Picker(),
        detector: DetectionServiceGateway(
          detector: DetectionService(
            faceDetector: _FakeFaceDetector(
              DetectionResult.empty(),
            ),
          ),
        ),
        exporter: (source, stamps) => Uint8List.fromList(<int>[1]),
        saver: _Saver(),
        history: const _History(),
      );
      final result = await controller.pickImage();

      expect(result, PickImageResult.detectionEmpty);
      expect(controller.detections, isEmpty);
      expect(controller.automaticCount, 0);
    });

    test('detectionFailed when detector throws', () async {
      final controller = StampController(
        picker: const _Picker(),
        detector: DetectionServiceGateway(
          detector: DetectionService(
            faceDetector: const _ThrowingFaceDetector(),
          ),
        ),
        exporter: (source, stamps) => Uint8List.fromList(<int>[1]),
        saver: _Saver(),
        history: const _History(),
      );
      final result = await controller.pickImage();

      expect(result, PickImageResult.detectionFailed);
      expect(controller.detections, isEmpty);
      expect(controller.lastDetectionSummary!.faces.isException, isTrue);
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
