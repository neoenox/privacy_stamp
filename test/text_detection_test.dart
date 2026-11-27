import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:privacy_stamp/features/redaction/detection/detector_service.dart';
import 'package:privacy_stamp/features/redaction/detection/text_detector.dart';
import 'package:privacy_stamp/features/redaction/models/redaction_models.dart';

class _FakeTextDetector implements TextRegionDetector {
  const _FakeTextDetector(this.regions);

  final List<RecognizedTextRegion> regions;

  @override
  Future<TextDetectionResult> detect(Uint8ListImageInput input) async =>
      TextDetectionResult.fromRegions(regions);
}

class _ThrowingTextDetector implements TextRegionDetector {
  const _ThrowingTextDetector();

  @override
  Future<TextDetectionResult> detect(Uint8ListImageInput input) async =>
      throw StateError('private implementation detail');
}

void main() {
  group('OCR auto-stamp diagnostics', () {
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
      expect(service.lastSummary!.text.isSuccess, isTrue);
    });

    test(
      'text detector exception remains distinguishable from empty OCR',
      () async {
        final service = DetectionService(
          textDetector: const _ThrowingTextDetector(),
        );
        final regions = await service.inspect(
          Uint8ListImageInput(Uint8List.fromList([1, 2, 3])),
        );
        expect(regions, isEmpty);
        expect(service.lastSummary!.text.isException, isTrue);
        expect(service.lastSummary!.hasAnyException, isTrue);
        expect(service.lastSummary!.text.error, 'text detection failed');
        },
    );

    test('genuine empty OCR result is not an exception', () async {
      final service = DetectionService(
        textDetector: const _FakeTextDetector([]),
      );
      await service.inspect(Uint8ListImageInput(Uint8List.fromList([1, 2, 3])));
      expect(service.lastSummary!.text.outcome, DetectionOutcome.empty);
      expect(service.lastSummary!.hasAnyException, isFalse);
    });

    test(
      'MlKitTextDetector returns a diagnostic for invalid image input',
      () async {
        final detector = MlKitTextDetector();
        final result = await detector.detect(
          Uint8ListImageInput(Uint8List.fromList([0, 1, 2, 3])),
        );
        expect(
          result.outcome,
          anyOf(DetectionOutcome.exception, DetectionOutcome.unsupported),
        );
        expect(result.regions, isEmpty);
        },
    );

    test('NoopTextDetector returns a genuine empty result', () async {
      final result = await const NoopTextDetector().detect(
        Uint8ListImageInput(Uint8List.fromList([1])),
      );
      expect(result.outcome, DetectionOutcome.empty);
      expect(result.regions, isEmpty);
    });
  });
}
