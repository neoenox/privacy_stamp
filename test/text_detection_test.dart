import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:privacy_stamp/features/redaction/detection/detector_service.dart';
import 'package:privacy_stamp/features/redaction/detection/text_detector.dart';
import 'package:privacy_stamp/features/redaction/models/redaction_models.dart';

class _FakeTextDetector implements TextRegionDetector {
  const _FakeTextDetector(this.regions);

  final List<RecognizedTextRegion> regions;

  @override
  Future<List<RecognizedTextRegion>> detect(Uint8ListImageInput input) async =>
      regions;
}

class _ThrowingTextDetector implements TextRegionDetector {
  const _ThrowingTextDetector();

  @override
  Future<List<RecognizedTextRegion>> detect(Uint8ListImageInput input) async =>
      throw StateError('no model');
}

void main() {
  group('ocr auto-stamp', () {
    test('DetectionService turns recognized email into text hits', () async {
      final service = DetectionService(
        textDetector: const _FakeTextDetector([
          RecognizedTextRegion(
            text: 'contact test@example.com',
            normalizedRect: NormalizedRect(.1, .1, .3, .1),
          ),
        ]),
      );
      final regions = await service.inspect(
        Uint8ListImageInput(Uint8List.fromList([1, 2, 3])),
      );
      expect(regions.where((r) => r.kind == DetectionKind.email), hasLength(1));
      expect(regions.single.sourceDetector, 'ocr-rules');
    });

    test('text detector failure degrades to empty, not throw', () async {
      final service = DetectionService(
        textDetector: const _ThrowingTextDetector(),
      );
      final regions = await service.inspect(
        Uint8ListImageInput(Uint8List.fromList([1, 2, 3])),
      );
      expect(regions, isEmpty);
    });

    test(
      'MlKitTextDetector returns empty without throwing off-device',
      () async {
        // No platform plugin on the test host: must degrade gracefully.
        final detector = MlKitTextDetector();
        final regions = await detector.detect(
          Uint8ListImageInput(Uint8List.fromList([0, 1, 2, 3])),
        );
        expect(regions, isEmpty);
      },
    );

    test('NoopTextDetector returns empty', () async {
      final regions = await const NoopTextDetector().detect(
        Uint8ListImageInput(Uint8List.fromList([1])),
      );
      expect(regions, isEmpty);
    });
  });
}
