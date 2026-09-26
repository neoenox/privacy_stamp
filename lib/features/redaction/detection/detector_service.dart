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
    List<RecognizedTextRegion> textRegions;
    try {
      textRegions = await _textDetector.detect(input);
    } catch (_) {
      textRegions = const [];
    }
    final textHits = _rules.detect(textRegions, hideAllText: hideAllText);

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
      textHits: textHits,
      textRegions: textRegions,
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
          textHits: regions,
          textRegions: const [],
        );
  }
}

class DetectionSummary {
  DetectionSummary({
    required this.faces,
    required this.codes,
    required this.textHits,
    required this.textRegions,
  });

  final DetectionResult faces;
  final DetectionResult codes;
  final List<DetectionRegion> textHits;
  final List<RecognizedTextRegion> textRegions;

  List<DetectionRegion> get allRegions => [...faces.regions, ...codes.regions, ...textHits];

  bool get hasFaceException => faces.isException;
  bool get hasCodeException => codes.isException;
  bool get hasAnyException => faces.isException || codes.isException;
}
