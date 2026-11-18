import '../models/redaction_models.dart';
import '../rules/sensitive_rules.dart';
import 'barcode_detector.dart';
import 'face_detector.dart';
import 'text_detector.dart';

class DetectionService {
  DetectionService({
    SensitiveRuleEngine? rules,
    FaceRegionDetector? faceDetector,
    TextRegionDetector? textDetector,
    CodeRegionDetector? codeDetector,
  }) : _rules = rules ?? SensitiveRuleEngine(),
       _faceDetector = faceDetector ?? const NoopFaceDetector(),
       _textDetector = textDetector ?? const NoopTextDetector(),
       _codeDetector = codeDetector ?? const NoopCodeDetector();

  final SensitiveRuleEngine _rules;
  final FaceRegionDetector _faceDetector;
  final TextRegionDetector _textDetector;
  final CodeRegionDetector _codeDetector;

  DetectionSummary? lastSummary;

  Future<List<DetectionRegion>> inspect(
    Uint8ListImageInput input, {
    bool hideAllText = false,
  }) async {
    TextDetectionResult textResult;
    try {
      textResult = await _textDetector.detect(input);
    } catch (_) {
      textResult = TextDetectionResult.exception(
        error: 'text detection failed',
      );
    }
    final textHits = _rules.detect(
      textResult.regions,
      hideAllText: hideAllText,
    );

    DetectionResult faceResult;
    try {
      faceResult = await _faceDetector.detect(input);
    } catch (_) {
      faceResult = DetectionResult.exception(error: 'face detection failed');
    }

    DetectionResult codeResult;
    try {
      final codeRegions = await _codeDetector.detect(input);
      codeResult = DetectionResult(
        regions: codeRegions,
        outcome: codeRegions.isEmpty
            ? DetectionOutcome.empty
            : DetectionOutcome.success,
      );
    } catch (_) {
      codeResult = DetectionResult.exception(error: 'code detection failed');
    }

    lastSummary = DetectionSummary(
      faces: faceResult,
      codes: codeResult,
      text: textResult,
      textHits: textHits,
    );

    return [...faceResult.regions, ...codeResult.regions, ...textHits];
  }

  Future<DetectionSummary> inspectWithDiagnostics(
    Uint8ListImageInput input, {
    bool hideAllText = false,
  }) async {
    final regions = await inspect(input, hideAllText: hideAllText);
    return lastSummary ??
        DetectionSummary(
          faces: DetectionResult.empty(),
          codes: DetectionResult.empty(),
          text: TextDetectionResult.empty(),
          textHits: regions,
        );
  }
}

class DetectionSummary {
  DetectionSummary({
    required this.faces,
    required this.codes,
    required this.text,
    required this.textHits,
  });

  final DetectionResult faces;
  final DetectionResult codes;
  final TextDetectionResult text;
  final List<DetectionRegion> textHits;

  List<DetectionRegion> get allRegions => [
    ...faces.regions,
    ...codes.regions,
    ...textHits,
  ];

  bool get hasFaceException => faces.isException;
  bool get hasCodeException => codes.isException;
  bool get hasTextException => text.isException;
  bool get hasTextUnsupported => text.isUnsupported;
  bool get hasAnyException =>
      faces.isException || codes.isException || text.isException;
  bool get hasAnyFailure => hasAnyException || hasTextUnsupported;
}
