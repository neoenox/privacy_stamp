import 'redaction_coordinates.dart';

export 'redaction_coordinates.dart';

enum DetectionKind {
  face,
  code,
  email,
  phone,
  postalCode,
  card,
  coordinate,
  labelledText,
  allText,
  statusRegion,
}

enum Certainty { automatic, review }

class DetectionRegion {
  DetectionRegion({
    required this.id,
    required this.kind,
    required this.normalizedRect,
    this.confidence = 1,
    this.certainty = Certainty.automatic,
    this.reason = '',
    this.sourceDetector = 'local',
    this.isEnabled = true,
  });
  final String id;
  final DetectionKind kind;
  final NormalizedRect normalizedRect;
  final double confidence;
  final Certainty certainty;
  final String reason;
  final String sourceDetector;
  bool isEnabled;
}

class RecognizedTextRegion {
  const RecognizedTextRegion({
    required this.text,
    required this.normalizedRect,
    this.confidence = 1,
  });
  final String text;
  final NormalizedRect normalizedRect;
  final double confidence;
}

class Stamp {
  Stamp({
    required this.id,
    required this.rect,
    this.kind = 'black',
    this.isAutomatic = false,
  });
  final String id;
  NormalizedRect rect;
  String kind;
  final bool isAutomatic;
}

enum DetectionOutcome { empty, success, exception }

class DetectionResult {
  DetectionResult({
    required this.regions,
    this.outcome = DetectionOutcome.empty,
    this.error,
    this.width,
    this.height,
    this.faceCount,
  });

  factory DetectionResult.exception({
    String? error,
    dynamic stackTrace,
  }) =>
      DetectionResult(
        regions: const [],
        outcome: DetectionOutcome.exception,
        error: error,
      );

  factory DetectionResult.empty() =>
      const DetectionResult(outcome: DetectionOutcome.empty);

  final List<DetectionRegion> regions;
  final DetectionOutcome outcome;
  final String? error;
  final int? width;
  final int? height;
  final int? faceCount;

  bool get isEmpty => regions.isEmpty;
  bool get isSuccess => outcome == DetectionOutcome.success;
  bool get isException => outcome == DetectionOutcome.exception;
}

abstract interface class FaceRegionDetector {
  Future<DetectionResult> detect(Uint8ListImageInput input);
}

abstract interface class TextRegionDetector {
  Future<List<RecognizedTextRegion>> detect(Uint8ListImageInput input);
}

abstract interface class CodeRegionDetector {
  Future<List<DetectionRegion>> detect(Uint8ListImageInput input);
}

class Uint8ListImageInput {
  const Uint8ListImageInput(this.bytes, {this.mimeType});
  final List<int> bytes;
  final String? mimeType;
}
