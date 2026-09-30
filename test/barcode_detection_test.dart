import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:privacy_stamp/features/redaction/detection/barcode_detector.dart';
import 'package:privacy_stamp/features/redaction/detection/detector_service.dart';
import 'package:privacy_stamp/features/redaction/models/redaction_models.dart';

class _FakeCodeDetector implements CodeRegionDetector {
  const _FakeCodeDetector(this.regions);

  final List<DetectionRegion> regions;

  @override
  Future<List<DetectionRegion>> detect(Uint8ListImageInput input) async =>
      regions;
}

class _ThrowingCodeDetector implements CodeRegionDetector {
  const _ThrowingCodeDetector();

  @override
  Future<List<DetectionRegion>> detect(Uint8ListImageInput input) async =>
      throw StateError('no model');
}

void main() {
  group('barcode auto-stamp', () {
    test('DetectionService merges barcode candidates', () async {
      final service = DetectionService(
        codeDetector: _FakeCodeDetector([
          DetectionRegion(
            id: 'code-0',
            kind: DetectionKind.code,
            normalizedRect: const NormalizedRect(.2, .2, .3, .2),
            reason: 'バーコード (qrCode)',
            sourceDetector: 'mlkit-barcode',
          ),
        ]),
      );
      final regions = await service.inspect(
        Uint8ListImageInput(Uint8List.fromList([1, 2, 3])),
      );
      expect(regions, hasLength(1));
      expect(regions.single.kind, DetectionKind.code);
    });

    test('barcode detector failure degrades to empty, not throw', () async {
      final service = DetectionService(
        codeDetector: const _ThrowingCodeDetector(),
      );
      final regions = await service.inspect(
        Uint8ListImageInput(Uint8List.fromList([1, 2, 3])),
      );
      expect(regions, isEmpty);
    });

    test(
      'MlKitBarcodeDetector returns empty without throwing off-device',
      () async {
        // No platform plugin on the test host: must degrade gracefully.
        final detector = MlKitBarcodeDetector();
        final regions = await detector.detect(
          Uint8ListImageInput(Uint8List.fromList([0, 1, 2, 3])),
        );
        expect(regions, isEmpty);
      },
    );

    test('NoopCodeDetector returns empty', () async {
      final regions = await const NoopCodeDetector().detect(
        Uint8ListImageInput(Uint8List.fromList([1])),
      );
      expect(regions, isEmpty);
    });
  });
}
